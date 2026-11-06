//
//  DownloadButtonView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews

struct DownloadButtonView: View {
	let sourceURL: URL?
	let source: ASRepository?
	let app: ASRepository.App
	/// Smaller pills for list rows.
	var compact: Bool = false
	@ObservedObject private var downloadManager = DownloadManager.shared

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?

	var body: some View {
		ZStack {
			if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
				ZStack {
					// faint full ring so the button is readable even before the first byte arrives
					Circle()
						.stroke(Color.accentColor.opacity(0.22), lineWidth: 2.3)
						.frame(width: 31, height: 31)

					Circle()
						.trim(from: 0, to: downloadProgress)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 31, height: 31)
						.animation(.smooth, value: downloadProgress)

					Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
						.foregroundStyle(.tint)
						.font(.footnote).bold()
				}
				.onTapGesture {
					if downloadProgress <= 0.75 {
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else {
				HStack(spacing: compact ? 6 : 8) {
					Button {
						if let url = app.currentDownloadUrl {
							// AppMaster: one tap = download -> sign -> install.
							// If there is no certificate yet, `begin` tells the person
							// and the app is simply saved in the Library like before.
							let autoInstall = OneTapInstaller.shared.begin(name: app.currentName)
							DownloadCounter.report(url: url)
							_ = downloadManager.startDownload(
								from: url,
								id: app.currentUniqueId,
								sourceProvenance: _sourceProvenance(),
								autoInstall: autoInstall
							)
						}
					} label: {
						_pill(.localized("Install"), prominent: true)
					}
					.buttonStyle(.borderless)

					Button {
						if let url = app.currentDownloadUrl {
							// download, then open the signing screen for this app
							_ = OneTapInstaller.shared.begin(name: app.currentName, customize: true)
							DownloadCounter.report(url: url)
							_ = downloadManager.startDownload(
								from: url,
								id: app.currentUniqueId,
								sourceProvenance: _sourceProvenance(),
								autoInstall: true
							)
						}
					} label: {
						_pill(.localized("Customize"), prominent: false)
					}
					.buttonStyle(.borderless)
				}
				.compatTransition()
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
	}

	@ViewBuilder
	private func _pill(_ title: String, prominent: Bool) -> some View {
		Text(title)
			.lineLimit(1)
			.minimumScaleFactor(0.8)
			.font((compact ? Font.subheadline : Font.headline).bold())
			.foregroundStyle(Color.accentColor)
			.padding(.horizontal, compact ? 12 : 20)
			.padding(.vertical, compact ? 5 : 6)
			.background(Color(uiColor: prominent ? .quaternarySystemFill : .quaternarySystemFill).opacity(prominent ? 1 : 0.6))
			.clipShape(Capsule())
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			downloadProgress = 0
			return
		}
		downloadProgress = download.overallProgress

		let publisher = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)

		cancellable = publisher.sink { _, _ in
			downloadProgress = download.overallProgress
		}
	}
	
	private func _sourceProvenance() -> SourceAppProvenance? {
		guard let source else { return nil }
		return SourceAppProvenance(sourceURL: sourceURL, repository: source, app: app)
	}
}
