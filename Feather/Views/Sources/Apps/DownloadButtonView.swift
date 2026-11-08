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
						.font(AppFont.footnote).bold()
				}
				.onTapGesture {
					if downloadProgress <= 0.75 {
						downloadManager.cancelDownload(currentDownload)
					}
				}
				.compatTransition()
			} else {
				HStack(spacing: compact ? 5 : 6) {
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
						// the signing screen opens right away (nothing is downloaded yet);
						// "Install" there starts download -> sign -> install in the background
						let installer = OneTapInstaller.shared
						let manager = DownloadManager.shared
						let provenance = _sourceProvenance()
						let target = app
						installer.pendingCustomize = PendingCustomize(
							name: app.currentName,
							identifier: app.id,
							version: app.currentVersion,
							iconURL: app.iconURL
						) { customization in
							guard let url = target.currentDownloadUrl else { return }
							let autoInstall = installer.begin(name: target.currentName, customization: customization)
							DownloadCounter.report(url: url)
							_ = manager.startDownload(
								from: url,
								id: target.currentUniqueId,
								sourceProvenance: provenance,
								autoInstall: autoInstall
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
			.font(AppFont.footnote.bold())
			.foregroundStyle(Color.accentColor)
			.padding(.horizontal, compact ? 10 : 14)
			.padding(.vertical, compact ? 3 : 5)
			.background(AppTheme.pill.opacity(prominent ? 1 : 0.7))
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
