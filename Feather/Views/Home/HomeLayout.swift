//
//  HomeLayout.swift
//  AppMaster
//
//  The order and content of the Home sections come from the dashboard
//  (Banner management > Home layout, served by the `home-layout` function):
//   - slides   : a carousel of cards (image / GIF / video + app icon, name,
//                title, subtitle and a download button)
//   - marquee  : moving rows of app icons
//   - featured : the classic "Featured" carousel
//   - lists    : the category rows (Apps / Games)
//

import SwiftUI
import Combine
import AVFoundation
import ImageIO
import AltSourceKit
import NimbleViews
import NukeUI

// MARK: - Model
struct HomeLayoutApp: Codable, Hashable {
	var name: String?
	var icon: String?
	var bundle_id: String?
	var ipa_url: String?
}

struct HomeLayoutSlide: Codable, Hashable {
	var media_type: String?
	var media_url: String?
	var title: String?
	var subtitle: String?
	var app: HomeLayoutApp?
}

struct HomeLayoutBlock: Codable, Identifiable, Hashable {
	var id: String
	var kind: String
	var title: String?
	var slides: [HomeLayoutSlide]?
	var apps: [HomeLayoutApp]?
}

private struct HomeLayoutResponse: Codable {
	var blocks: [HomeLayoutBlock]
}

// MARK: - Store
@MainActor
final class HomeLayoutStore: ObservableObject {
	static let shared = HomeLayoutStore()

	/// nil = nothing known yet (the classic Home is shown)
	@Published private(set) var blocks: [HomeLayoutBlock]?

	private let _cacheKey = "appmaster.home.layout.cache"
	private let _url = URL(string: "https://seemtaruyoixqdfdqwfv.supabase.co/functions/v1/home-layout")!

	private init() {
		if let data = UserDefaults.standard.data(forKey: _cacheKey),
		   let response = try? JSONDecoder().decode(HomeLayoutResponse.self, from: data) {
			blocks = response.blocks
		}
	}

	func refresh() async {
		var request = URLRequest(url: _url)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		request.timeoutInterval = 15
		guard let (data, response) = try? await URLSession.shared.data(for: request),
			  (response as? HTTPURLResponse)?.statusCode == 200,
			  let decoded = try? JSONDecoder().decode(HomeLayoutResponse.self, from: data) else { return }
		UserDefaults.standard.set(data, forKey: _cacheKey)
		blocks = decoded.blocks
	}
}

// MARK: - Matching a dashboard app with the catalog app
enum HomeLayoutMatcher {
	static func resolve(_ app: HomeLayoutApp?, in repo: ASRepository) -> ASRepository.App? {
		guard let app else { return nil }
		if let ipa = app.ipa_url, !ipa.isEmpty,
		   let found = repo.apps.first(where: { $0.downloadURL?.absoluteString == ipa }) {
			return found
		}
		if let bundle = app.bundle_id, !bundle.isEmpty {
			return repo.apps.first(where: { $0.id == bundle })
		}
		return nil
	}
}

/// Built once per section so every tile is matched with a dictionary lookup
/// instead of scanning the whole catalog each time.
struct HomeLayoutIndex {
	private var _byIPA: [String: ASRepository.App] = [:]
	private var _byBundle: [String: ASRepository.App] = [:]

	init(_ repo: ASRepository) {
		for app in repo.apps {
			if let ipa = app.downloadURL?.absoluteString, _byIPA[ipa] == nil { _byIPA[ipa] = app }
			if let id = app.id, _byBundle[id] == nil { _byBundle[id] = app }
		}
	}

	func resolve(_ app: HomeLayoutApp?) -> ASRepository.App? {
		guard let app else { return nil }
		if let ipa = app.ipa_url, !ipa.isEmpty, let found = _byIPA[ipa] { return found }
		if let bundle = app.bundle_id, !bundle.isEmpty { return _byBundle[bundle] }
		return nil
	}
}

// MARK: - Video (muted, looping, fills its frame)
private final class LoopingPlayerView: UIView {
	override class var layerClass: AnyClass { AVPlayerLayer.self }
	private var _playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
	private var _player: AVQueuePlayer?
	private var _looper: AVPlayerLooper?

	func configure(url: URL) {
		try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
		let player = AVQueuePlayer()
		player.isMuted = true
		_looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
		_playerLayer.player = player
		_playerLayer.videoGravity = .resizeAspectFill
		_player = player
	}

	func setPlaying(_ playing: Bool) {
		if playing { _player?.play() } else { _player?.pause() }
	}
}

private struct LoopingVideoView: UIViewRepresentable {
	let url: URL
	let isPlaying: Bool

	func makeUIView(context: Context) -> UIView {
		let view = LoopingPlayerView()
		view.backgroundColor = .black
		view.configure(url: url)
		view.setPlaying(isPlaying)
		return view
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		(uiView as? LoopingPlayerView)?.setPlaying(isPlaying)
	}

	static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
		(uiView as? LoopingPlayerView)?.setPlaying(false)
	}
}

// MARK: - GIF
private enum GIFLoader {
	static func load(_ url: URL) async -> UIImage? {
		guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
		return await Task.detached(priority: .userInitiated) { decode(data) }.value
	}

	private static func decode(_ data: Data) -> UIImage? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		let count = CGImageSourceGetCount(source)
		guard count > 0 else { return nil }
		if count == 1 { return UIImage(data: data) }

		let step = max(1, count / 40)
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceThumbnailMaxPixelSize: 480
		]
		var frames: [UIImage] = []
		var total: Double = 0
		var index = 0
		while index < count {
			if let cg = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
				frames.append(UIImage(cgImage: cg))
			}
			var delay = 0.1
			if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
			   let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
				let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
				let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
				delay = unclamped ?? clamped ?? 0.1
				if delay < 0.02 { delay = 0.1 }
			}
			total += delay * Double(step)
			index += step
		}
		guard !frames.isEmpty else { return nil }
		return UIImage.animatedImage(with: frames, duration: total)
	}
}

private struct AnimatedImageView: UIViewRepresentable {
	let image: UIImage?

	func makeUIView(context: Context) -> UIImageView {
		let view = UIImageView()
		view.contentMode = .scaleAspectFill
		view.clipsToBounds = true
		view.setContentHuggingPriority(.defaultLow, for: .horizontal)
		view.setContentHuggingPriority(.defaultLow, for: .vertical)
		view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		return view
	}

	func updateUIView(_ uiView: UIImageView, context: Context) {
		if uiView.image !== image {
			uiView.image = image
			if image != nil { uiView.startAnimating() }
		}
	}
}

private struct GIFView: View {
	let url: URL
	@State private var _image: UIImage?

	var body: some View {
		AnimatedImageView(image: _image)
			.task(id: url) {
				_image = await GIFLoader.load(url)
			}
	}
}

// MARK: - Slides
struct HomeSlidesSection: View {
	let block: HomeLayoutBlock
	let repo: ASRepository
	let sourceURL: URL?

	@State private var _page = 0

	private var _slides: [HomeLayoutSlide] { block.slides ?? [] }

	var body: some View {
		let index = HomeLayoutIndex(repo)
		VStack(alignment: .leading, spacing: 12) {
			if let title = block.title, !title.isEmpty {
				Text(title)
					.font(AppFont.title2.bold())
					.padding(.horizontal)
			}

			TabView(selection: $_page) {
				ForEach(Array(_slides.enumerated()), id: \.offset) { pageIndex, slide in
					_pageView(slide: slide, isActive: pageIndex == _page, index: index)
						.tag(pageIndex)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
			.frame(height: 510)

			if _slides.count > 1 {
				HStack(spacing: 6) {
					ForEach(0..<_slides.count, id: \.self) { dot in
						Circle()
							.fill(dot == _page ? Color.primary : Color.secondary.opacity(0.4))
							.frame(width: 6, height: 6)
					}
				}
				.frame(maxWidth: .infinity)
			}
		}
	}

	@ViewBuilder
	private func _pageView(slide: HomeLayoutSlide, isActive: Bool, index: HomeLayoutIndex) -> some View {
		let resolved = index.resolve(slide.app)
		ZStack(alignment: .bottomTrailing) {
			if let resolved {
				NavigationLink {
					SourceAppsDetailView(sourceURL: sourceURL, source: repo, app: resolved)
				} label: {
					HomeSlideCard(slide: slide, isActive: isActive, hasButton: true)
				}
				.buttonStyle(.plain)

				HomeSlideDownloadButton(sourceURL: sourceURL, source: repo, app: resolved)
					.padding(18)
			} else {
				HomeSlideCard(slide: slide, isActive: isActive, hasButton: false)
			}
		}
		.padding(.horizontal)
	}
}

/// Portrait pictures fill the card; wide ones are shown whole over a soft copy of themselves.
private struct HomeFitImage: View {
	let url: URL

	var body: some View {
		LazyImage(url: url) { state in
			if let image = state.image {
				let size = state.imageContainer?.image.size ?? .zero
				if size.height > 0 && size.width / size.height > 0.8 {
					ZStack {
						image.resizable().scaledToFill().opacity(0.35).blur(radius: 24)
						image.resizable().scaledToFit()
					}
				} else {
					image.resizable().scaledToFill()
				}
			} else {
				Color.black
			}
		}
	}
}

private struct HomeSlideCard: View {
	let slide: HomeLayoutSlide
	let isActive: Bool
	let hasButton: Bool

	private var _mediaURL: URL? {
		guard let raw = slide.media_url else { return nil }
		return URL(string: raw)
	}

	var body: some View {
		Color.black
			.overlay { _media }
			.overlay(alignment: .bottom) { _fog }
			.overlay(alignment: .bottom) { _texts }
			.frame(height: 500)
			.clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
	}

	@ViewBuilder
	private var _media: some View {
		GeometryReader { proxy in
			Group {
				if let url = _mediaURL {
					switch slide.media_type {
					case "video":
						LoopingVideoView(url: url, isPlaying: isActive)
					case "gif":
						GIFView(url: url)
					default:
						HomeFitImage(url: url)
					}
				}
			}
			.frame(width: proxy.size.width, height: proxy.size.height)
			.clipped()
		}
	}

	/// soft graduated haze behind the text
	private var _fog: some View {
		LinearGradient(
			colors: [.clear, Color.black.opacity(0.45), Color.black.opacity(0.85)],
			startPoint: .top,
			endPoint: .bottom
		)
		.frame(height: 190)
		.allowsHitTesting(false)
	}

	private var _texts: some View {
		VStack(alignment: .leading, spacing: 7) {
			if let app = slide.app {
				HStack(spacing: 8) {
					if let raw = app.icon, let url = URL(string: raw) {
						LazyImage(url: url) { state in
							if let image = state.image {
								image.appIconStyle(size: 26)
							} else {
								Image("App_Unknown").appIconStyle(size: 26)
							}
						}
					}
					Text(app.name ?? "")
						.font(AppFont.footnote.weight(.semibold))
						.foregroundStyle(.white.opacity(0.8))
						.lineLimit(1)
				}
			}
			if let title = slide.title, !title.isEmpty {
				Text(title)
					.font(AppFont.title2.bold())
					.foregroundStyle(.white)
					.lineLimit(3)
					.multilineTextAlignment(.leading)
			}
			if let subtitle = slide.subtitle, !subtitle.isEmpty {
				Text(subtitle)
					.font(AppFont.subheadline)
					.foregroundStyle(.white.opacity(0.75))
					.lineLimit(2)
					.multilineTextAlignment(.leading)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.leading, 18)
		.padding(.trailing, hasButton ? 110 : 18)
		.padding(.bottom, 18)
		.allowsHitTesting(false)
	}
}

// MARK: - Download button on a slide (takes the place of the old "save" button)
private struct HomeSlideDownloadButton: View {
	let sourceURL: URL?
	let source: ASRepository
	let app: ASRepository.App

	@ObservedObject private var downloadManager = DownloadManager.shared
	@State private var _progress: Double = 0
	@State private var _cancellable: AnyCancellable?

	var body: some View {
		ZStack {
			if let current = downloadManager.getDownload(by: app.currentUniqueId) {
				ZStack {
					Circle()
						.stroke(Color.white.opacity(0.25), lineWidth: 2.6)
						.frame(width: 30, height: 30)
					Circle()
						.trim(from: 0, to: _progress)
						.stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 30, height: 30)
						.animation(.smooth, value: _progress)
					Image(systemName: _progress >= 0.75 ? "archivebox" : "square.fill")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.white)
				}
				.frame(width: 46, height: 46)
				.background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
				.onTapGesture {
					if _progress <= 0.75 {
						downloadManager.cancelDownload(current)
					}
				}
			} else {
				Button {
					_start()
				} label: {
					Text(.localized("Install"))
						.font(AppFont.subheadline.weight(.bold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.padding(.horizontal, 20)
						.padding(.vertical, 9)
						.background(Color.white.opacity(0.22), in: Capsule())
				}
				.buttonStyle(.plain)
			}
		}
		.environment(\.colorScheme, .dark)
		.onAppear(perform: _observe)
		.onDisappear { _cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			_observe()
		}
	}

	private func _start() {
		guard let url = app.currentDownloadUrl else { return }
		let autoInstall = OneTapInstaller.shared.begin(name: app.currentName)
		DownloadCounter.report(url: url)
		_ = downloadManager.startDownload(
			from: url,
			id: app.currentUniqueId,
			sourceProvenance: SourceAppProvenance(sourceURL: sourceURL, repository: source, app: app),
			autoInstall: autoInstall
		)
	}

	private func _observe() {
		_cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			_progress = 0
			return
		}
		_progress = download.overallProgress
		_cancellable = Publishers.CombineLatest(download.$progress, download.$unpackageProgress)
			.sink { _, _ in
				_progress = download.overallProgress
			}
	}
}

// MARK: - Moving app icons
private struct MarqueeRow<Tile: View>: View {
	let items: [HomeLayoutApp]
	let reverse: Bool
	let tile: (HomeLayoutApp) -> Tile

	@State private var _go = false

	private let _size: CGFloat = 66
	private let _gap: CGFloat = 14
	private let _speed: Double = 26

	private var _unit: [HomeLayoutApp] {
		guard !items.isEmpty else { return [] }
		var out: [HomeLayoutApp] = []
		while out.count < 8 { out.append(contentsOf: items) }
		return out
	}

	var body: some View {
		let unit = _unit
		let period = CGFloat(unit.count) * (_size + _gap)
		let duration = Double(period) / _speed
		let from: CGFloat = reverse ? -period : 0
		let to: CGFloat = reverse ? 0 : -period
		let animation: Animation? = _go ? Animation.linear(duration: duration).repeatForever(autoreverses: false) : nil
		// the moving strip lives in an overlay so its (very wide) content never
		// widens the Home page — only the clear box below takes part in the layout
		Color.clear
			.frame(height: _size)
			.overlay(alignment: .leading) {
				HStack(spacing: _gap) {
					ForEach(0..<(unit.count * 2), id: \.self) { position in
						tile(unit[position % unit.count])
							.frame(width: _size, height: _size)
					}
				}
				.fixedSize()
				.offset(x: _go ? to : from)
				.animation(animation, value: _go)
			}
			.clipped()
		.onAppear { _go = true }
		.onDisappear { _go = false }
	}
}

struct HomeMarqueeSection: View {
	let block: HomeLayoutBlock
	let repo: ASRepository
	let sourceURL: URL?

	private var _apps: [HomeLayoutApp] { block.apps ?? [] }

	private var _rows: [[HomeLayoutApp]] {
		if _apps.count > 4 {
			var first: [HomeLayoutApp] = []
			var second: [HomeLayoutApp] = []
			for (index, app) in _apps.enumerated() {
				if index % 2 == 0 { first.append(app) } else { second.append(app) }
			}
			return [first, second]
		}
		return [_apps]
	}

	var body: some View {
		let lookup = HomeLayoutIndex(repo)
		VStack(alignment: .leading, spacing: 12) {
			if let title = block.title, !title.isEmpty {
				Text(title)
					.font(AppFont.title2.bold())
					.padding(.horizontal)
			}
			VStack(spacing: 14) {
				ForEach(Array(_rows.enumerated()), id: \.offset) { index, row in
					MarqueeRow(items: row, reverse: index % 2 == 1) { app in
						_tile(app, lookup: lookup)
					}
				}
			}
			.environment(\.layoutDirection, .leftToRight)
		}
	}

	@ViewBuilder
	private func _tile(_ app: HomeLayoutApp, lookup: HomeLayoutIndex) -> some View {
		let icon = Group {
			if let raw = app.icon, let url = URL(string: raw) {
				LazyImage(url: url) { state in
					if let image = state.image {
						image.appIconStyle(size: 66)
					} else {
						Image("App_Unknown").appIconStyle(size: 66)
					}
				}
			} else {
				Image("App_Unknown").appIconStyle(size: 66)
			}
		}
		if let resolved = lookup.resolve(app) {
			NavigationLink {
				SourceAppsDetailView(sourceURL: sourceURL, source: repo, app: resolved)
			} label: {
				icon
			}
			.buttonStyle(.plain)
		} else {
			icon
		}
	}
}

// MARK: - Featured apps (chosen from the dashboard)
struct HomeFeaturedSection: View {
	let block: HomeLayoutBlock
	let repo: ASRepository
	let sourceURL: URL?

	private var _items: [ASRepository.App] {
		let index = HomeLayoutIndex(repo)
		return (block.apps ?? []).compactMap { index.resolve($0) }
	}

	var body: some View {
		let items = _items
		if !items.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				if let title = block.title, !title.isEmpty {
					Text(title)
						.font(AppFont.title2.bold())
						.padding(.horizontal)
				}
				TabView {
					ForEach(items, id: \.currentUniqueId) { app in
						NavigationLink {
							SourceAppsDetailView(sourceURL: sourceURL, source: repo, app: app)
						} label: {
							_card(app)
						}
						.buttonStyle(.plain)
					}
				}
				.tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
				.frame(height: 220)
			}
		}
	}

	@ViewBuilder
	private func _card(_ app: ASRepository.App) -> some View {
		ZStack(alignment: .bottomLeading) {
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(app.tintColor ?? Color.accentColor)
				.opacity(0.85)
			HStack(spacing: 16) {
				if let iconURL = app.iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
							image.appIconStyle(size: 72)
						}
					}
				}
				VStack(alignment: .leading, spacing: 4) {
					Text(app.currentName)
						.font(AppFont.title3.bold())
						.foregroundStyle(.white)
					if let subtitle = app.currentDescription {
						Text(subtitle)
							.font(AppFont.subheadline)
							.foregroundStyle(.white.opacity(0.9))
							.lineLimit(2)
					}
				}
				Spacer()
			}
			.padding(20)
		}
		.padding(.horizontal)
	}
}

// MARK: - Row of apps (chosen from the dashboard)
struct HomeAppsRowSection: View {
	let block: HomeLayoutBlock
	let repo: ASRepository
	let sourceURL: URL?

	private var _apps: [ASRepository.App] {
		let index = HomeLayoutIndex(repo)
		return (block.apps ?? []).compactMap { index.resolve($0) }
	}

	var body: some View {
		let apps = _apps
		if !apps.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				if let title = block.title, !title.isEmpty {
					Text(title)
						.font(AppFont.title3.bold())
						.padding(.horizontal)
				}
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(spacing: 16) {
						ForEach(apps, id: \.currentUniqueId) { app in
							NavigationLink {
								SourceAppsDetailView(sourceURL: sourceURL, source: repo, app: app)
							} label: {
								_tile(app)
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal)
				}
			}
		}
	}

	@ViewBuilder
	private func _tile(_ app: ASRepository.App) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			if let iconURL = app.iconURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.appIconStyle(size: 90)
					} else {
						Image("App_Unknown").appIconStyle(size: 90)
					}
				}
			} else {
				Image("App_Unknown").appIconStyle(size: 90)
			}
			Text(app.currentName)
				.font(AppFont.footnote.weight(.medium))
				.lineLimit(1)
				.frame(width: 90, alignment: .leading)
		}
	}
}

// MARK: - Lists (App Store style columns of three apps)
struct HomeListsSection: View {
	let block: HomeLayoutBlock
	let repo: ASRepository
	let sourceURL: URL?

	private var _apps: [ASRepository.App] {
		let index = HomeLayoutIndex(repo)
		return (block.apps ?? []).compactMap { index.resolve($0) }
	}

	var body: some View {
		let apps = _apps
		if !apps.isEmpty {
			let columns: [[ASRepository.App]] = stride(from: 0, to: apps.count, by: 3).map { start in
				Array(apps[start..<min(start + 3, apps.count)])
			}
			VStack(alignment: .leading, spacing: 12) {
				if let title = block.title, !title.isEmpty {
					Text(title)
						.font(AppFont.title3.bold())
						.padding(.horizontal)
				}
				ScrollView(.horizontal, showsIndicators: false) {
					LazyHStack(alignment: .top, spacing: 16) {
						ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
							VStack(spacing: 14) {
								ForEach(column, id: \.currentUniqueId) { app in
									NavigationLink {
										SourceAppsDetailView(sourceURL: sourceURL, source: repo, app: app)
									} label: {
										_row(app)
									}
									.buttonStyle(.plain)
								}
							}
							.frame(width: 300)
						}
					}
					.padding(.horizontal)
				}
			}
		}
	}

	@ViewBuilder
	private func _row(_ app: ASRepository.App) -> some View {
		HStack(spacing: 12) {
			if let iconURL = app.iconURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.appIconStyle(size: 56)
					} else {
						Image("App_Unknown").appIconStyle(size: 56)
					}
				}
			} else {
				Image("App_Unknown").appIconStyle(size: 56)
			}
			Text(app.currentName)
				.font(AppFont.subheadline.weight(.semibold))
				.lineLimit(1)
			Spacer(minLength: 0)
		}
	}
}
