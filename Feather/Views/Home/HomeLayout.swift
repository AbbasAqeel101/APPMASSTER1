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

		let step = max(1, count / 120)
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceThumbnailMaxPixelSize: 900
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
		VStack(alignment: .leading, spacing: 12) {
			if let title = block.title, !title.isEmpty {
				Text(title)
					.font(AppFont.title2.bold())
					.padding(.horizontal)
			}

			TabView(selection: $_page) {
				ForEach(Array(_slides.enumerated()), id: \.offset) { index, slide in
					_pageView(slide: slide, isActive: index == _page)
						.tag(index)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: .never))
			.frame(height: 430)

			if _slides.count > 1 {
				HStack(spacing: 6) {
					ForEach(0..<_slides.count, id: \.self) { index in
						Circle()
							.fill(index == _page ? Color.primary : Color.secondary.opacity(0.4))
							.frame(width: 6, height: 6)
					}
				}
				.frame(maxWidth: .infinity)
			}
		}
	}

	@ViewBuilder
	private func _pageView(slide: HomeLayoutSlide, isActive: Bool) -> some View {
		let resolved = HomeLayoutMatcher.resolve(slide.app, in: repo)
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
			.frame(height: 420)
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
						LazyImage(url: url) { state in
							if let image = state.image {
								image.resizable().scaledToFill()
							} else {
								Color.black
							}
						}
					}
				}
			}
			.frame(width: proxy.size.width, height: proxy.size.height)
			.clipped()
		}
	}

	/// soft graduated haze behind the text
	private var _fog: some View {
		ZStack {
			Rectangle()
				.fill(.ultraThinMaterial)
				.mask(
					LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom)
				)
			LinearGradient(
				colors: [.clear, Color.black.opacity(0.45), Color.black.opacity(0.85)],
				startPoint: .top,
				endPoint: .bottom
			)
		}
		.frame(height: 250)
		.environment(\.colorScheme, .dark)
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
		.padding(.trailing, hasButton ? 76 : 18)
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
				.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
				.onTapGesture {
					if _progress <= 0.75 {
						downloadManager.cancelDownload(current)
					}
				}
			} else {
				Button {
					_start()
				} label: {
					Image(systemName: "arrow.down")
						.font(.system(size: 18, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: 46, height: 46)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
		let period = Double(unit.count) * Double(_size + _gap)
		TimelineView(.animation) { context in
			let t = context.date.timeIntervalSinceReferenceDate * _speed
			let shift = t.truncatingRemainder(dividingBy: max(period, 1))
			let x = reverse ? -period + shift : -shift
			HStack(spacing: _gap) {
				ForEach(0..<(unit.count * 2), id: \.self) { index in
					tile(unit[index % unit.count])
						.frame(width: _size, height: _size)
				}
			}
			.offset(x: x)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(height: _size)
		.clipped()
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
		VStack(alignment: .leading, spacing: 12) {
			if let title = block.title, !title.isEmpty {
				Text(title)
					.font(AppFont.title2.bold())
					.padding(.horizontal)
			}
			VStack(spacing: 14) {
				ForEach(Array(_rows.enumerated()), id: \.offset) { index, row in
					MarqueeRow(items: row, reverse: index % 2 == 1) { app in
						_tile(app)
					}
				}
			}
			.environment(\.layoutDirection, .leftToRight)
		}
	}

	@ViewBuilder
	private func _tile(_ app: HomeLayoutApp) -> some View {
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
		if let resolved = HomeLayoutMatcher.resolve(app, in: repo) {
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
