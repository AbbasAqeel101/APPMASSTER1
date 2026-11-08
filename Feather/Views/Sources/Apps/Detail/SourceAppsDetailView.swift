//
//  SourceAppsDetailView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import NukeUI

// MARK: - SourceAppsDetailView
struct SourceAppsDetailView: View {
	@ObservedObject var downloadManager = DownloadManager.shared
	@ObservedObject private var _favorites = FavoritesStore.shared
	@State private var _downloadProgress: Double = 0
	@State var cancellable: AnyCancellable? // Combine
	@State private var _isScreenshotPreviewPresented: Bool = false
	@State private var _selectedScreenshotIndex: Int = 0
	@State private var _showEnglish: Bool = false
	
	var currentDownload: Download? {
		downloadManager.getDownload(by: app.currentUniqueId)
	}
	
	let sourceURL: URL?
	let source: ASRepository
	let app: ASRepository.App
	
	var body: some View {
		ScrollView {
			if #available(iOS 18, *) {
				_header().flexibleHeaderContent()
			}
			
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .center, spacing: 14) {
					if let iconURL = app.iconURL {
						LazyImage(url: iconURL) { state in
							if let image = state.image {
								image.appIconStyle(size: 96, isCircle: false)
							} else {
								standardIcon
							}
						}
					} else {
						standardIcon
					}

					VStack(alignment: .leading, spacing: 5) {
						Text(app.currentName)
							.font(AppFont.title3)
							.foregroundColor(.primary)
							.lineLimit(2)
							.frame(maxWidth: .infinity, alignment: .leading)

						// latest version, right under the name
						_versionLine()

						DownloadButtonView(sourceURL: sourceURL, source: source, app: app)
							.padding(.top, 2)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}

				Divider()
				_infoPills(app: app)
				Divider()
                
				_descriptionSection()

				if let screenshotURLs = app.screenshotURLs, !screenshotURLs.isEmpty {
					NBSection(.localized("Screenshots")) {
						_screenshots(screenshotURLs: screenshotURLs)
					}

					Divider()
				}

				if
					let currentVer = app.currentVersion,
					let whatsNewDesc = app.currentAppVersion?.localizedDescription
				{
					NBSection(.localized("What's New")) {
						AppVersionInfo(
							version: currentVer,
							date: app.currentDate?.date,
							description: whatsNewDesc
						)
						if let versions = app.versions {
							NavigationLink(
								destination: VersionHistoryView(
									sourceURL: sourceURL,
									source: source,
									app: app,
									versions: versions
								)
									.navigationTitle(.localized("Version History"))
									.navigationBarTitleDisplayMode(.large)
							) {
								Text(.localized("Version History"))
							}
						}
					}
					
					Divider()
				}
				
				NBSection(.localized("Information")) {
					VStack(spacing: 12) {
						if let sourceName = source.name {
							_infoRow(title: .localized("Source"), value: sourceName)
						}
                        
						if let developer = app.developer {
							_infoRow(title: .localized("Developer"), value: developer)
						}
						
						if let size = app.size {
							_infoRow(title: .localized("Size"), value: size.formattedByteCount)
						}
						
						if let category = app.category, !category.isEmpty {
							_infoRow(title: .localized("Category"), value: category.capitalized)
						}
						
						if let version = app.currentVersion {
							_infoRow(title: .localized("Version"), value: version)
						}
						
						if let date = app.currentDate?.date {
							_infoRow(title: .localized("Updated"), value: DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
						}
						
						if let bundleId = app.id {
							_infoRow(title: .localized("Identifier"), value: bundleId)
						}
					}
				}
				
				if let appPermissions = app.appPermissions {
					NBSection(.localized("Permissions")) {
						Group {
							if let entitlements = appPermissions.entitlements {
								NBTitleWithSubtitleView(
									title: .localized("Entitlements"),
									subtitle: entitlements.map(\.name).joined(separator: "\n")
								)
							} else {
								Text(.localized("No Entitlements listed."))
									.font(AppFont.subheadline)
									.foregroundStyle(.secondary)
							}
							if let privacyItems = appPermissions.privacy {
								ForEach(privacyItems, id: \.self) { item in
									NBTitleWithSubtitleView(
										title: item.name,
										subtitle: item.usageDescription
									)
								}
							} else {
								Text(.localized("No Privacy Permissions listed."))
									.font(AppFont.subheadline)
									.foregroundStyle(.secondary)
							}
						}
						.padding()
						.background(
							RoundedRectangle(cornerRadius: 18, style: .continuous)
								.fill(AppTheme.pill)
						)
					}
				}
			}
			.padding([.horizontal, .bottom])
			.padding(.top, {
				if #available(iOS 18, *) {
					8
				} else {
					0
				}
			}())
		}
		.flexibleHeaderScrollView()
		.shouldSetInset()
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button {
						let sharedString = """
						\(app.currentName) - \(app.currentVersion ?? "0")
						\(app.currentDescription ?? .localized("An awesome application"))
						---
						\(source.website?.absoluteString ?? source.name ?? "")
						"""
						UIActivityViewController.show(activityItems: [sharedString])
					} label: {
						Label(.localized("Share"), systemImage: "square.and.arrow.up")
					}
					Button {
						_favorites.toggle(app)
					} label: {
						if _favorites.isFavorite(app) {
							Label(.localized("Remove from Favorites"), systemImage: "star.slash")
						} else {
							Label(.localized("Add to Favorites"), systemImage: "star")
						}
					}
				} label: {
					Image(systemName: "ellipsis")
				}
			}
		}
		.fullScreenCover(isPresented: $_isScreenshotPreviewPresented) {
			if let screenshotURLs = app.screenshotURLs {
				ScreenshotPreviewView(
					screenshotURLs: screenshotURLs,
					initialIndex: _selectedScreenshotIndex
				)
			}
		}
	}
	
	var standardIcon: some View {
		Image("App_Unknown").appIconStyle(size: 96, isCircle: false)
	}
	
	var standardHeader: some View {
		Image("App_Unknown")
			.resizable()
			.aspectRatio(contentMode: .fill)
			.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
			.clipped()
	}
}

// MARK: - SourceAppsDetailView (Extension): Builders
extension SourceAppsDetailView {
	@available(iOS 18.0, *)
	@ViewBuilder
	private func _header() -> some View {
		ZStack {
			if let iconURL = app.iconURL ?? source.currentIconURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.resizable()
							.aspectRatio(contentMode: .fill)
							.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
							.clipped()
					} else {
						standardHeader
					}
				}
			} else {
				standardHeader
			}
			
			NBVariableBlurView()
				.rotationEffect(.degrees(-180))
				.overlay(
					LinearGradient(
						gradient: Gradient(colors: [
							Color.black.opacity(0.8),
							Color.black.opacity(0)
						]),
						startPoint: .top,
						endPoint: .bottom
					)
				)
		}
	}
	
	@ViewBuilder
	private func _infoPills(app: ASRepository.App) -> some View {
		let pillItems = _buildPills(from: app)
		HStack(spacing: 6) {
			ForEach(pillItems.indices, id: \.hashValue) { index in
				let pill = pillItems[index]
				NBPillView(
					title: pill.title,
					icon: pill.icon,
					color: pill.color,
					index: index,
					count: pillItems.count
				)
			}
		}
	}
	
	private func _buildPills(from app: ASRepository.App) -> [NBPillItem] {
		var pills: [NBPillItem] = []
		let tint = Color.accentColor

		pills.append(NBPillItem(title: "\(app.downloads ?? 0)", icon: "arrow.down.circle", color: tint))

		if let size = app.size {
			pills.append(NBPillItem(title: size.formattedByteCount, icon: "archivebox", color: tint))
		}

		if let minOS = app.currentAppVersion?.minOSVersion {
			pills.append(NBPillItem(title: "iOS \(minOS.description)+", icon: "iphone", color: tint))
		}

		if let category = app.category, !category.isEmpty {
			pills.append(NBPillItem(title: category, icon: "square.grid.2x2", color: tint))
		}

		return pills
	}

	/// "Version 249.0 • 6 hours ago"
	@ViewBuilder
	private func _versionLine() -> some View {
		let parts = _versionParts()
		if !parts.isEmpty {
			Text(parts.joined(separator: "  •  "))
				.font(AppFont.footnote)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private func _versionParts() -> [String] {
		var parts: [String] = []
		if let version = app.currentVersion, !version.isEmpty {
			parts.append(String.localized("Version") + " " + version)
		}
		if let date = app.currentDate?.date {
			let formatter = RelativeDateTimeFormatter()
			formatter.unitsStyle = .full
			formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
			parts.append(formatter.localizedString(for: date, relativeTo: Date()))
		}
		return parts
	}

	private var _arabicDescription: String? {
		let value = (app.localizedDescription ?? app.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		return value.isEmpty ? nil : value
	}

	private var _englishDescription: String? {
		let value = (app.descriptionEN ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		return value.isEmpty ? nil : value
	}

	@ViewBuilder
	private func _descriptionSection() -> some View {
		let arabic = _arabicDescription
		let english = _englishDescription

		if arabic != nil || english != nil {
			let showEnglish = (_showEnglish && english != nil) || arabic == nil
			let text = (showEnglish ? english : arabic) ?? ""

			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text(.localized("Description"))
						.font(AppFont.title2)

					Spacer()

					if arabic != nil, english != nil {
						_languageSwitch(showEnglish: showEnglish)
					}
				}

				ExpandableText(text: text, lineLimit: 3)
					.id(showEnglish)
					.frame(maxWidth: .infinity, alignment: .leading)
			}

			Divider()
		}
	}

	@ViewBuilder
	private func _languageSwitch(showEnglish: Bool) -> some View {
		HStack(spacing: 2) {
			_languageButton("AR", isSelected: !showEnglish) { _showEnglish = false }
			_languageButton("EN", isSelected: showEnglish) { _showEnglish = true }
		}
		.padding(2)
		.background(AppTheme.pill, in: Capsule())
	}

	@ViewBuilder
	private func _languageButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Text(verbatim: title)
			.font(AppFont.caption.bold())
			.foregroundStyle(isSelected ? Color.white : Color.secondary)
			.padding(.horizontal, 12)
			.padding(.vertical, 4)
			.background(Capsule().fill(isSelected ? Color.accentColor : Color.clear))
			.contentShape(Capsule())
			.onTapGesture(perform: action)
	}

	@ViewBuilder
	private func _infoRow(title: String, value: String) -> some View {
		LabeledContent(title, value: value)
		Divider()
	}
	
	@ViewBuilder
	private func _screenshots(screenshotURLs: [URL]) -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 12) {
				ForEach(screenshotURLs.indices, id: \.self) { index in
					let url = screenshotURLs[index]
					LazyImage(url: url) { state in
						if let image = state.image {
							image
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(
									maxWidth: UIScreen.main.bounds.width * 0.62,
									maxHeight: 380
								)
								.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
								.overlay {
									RoundedRectangle(cornerRadius: 16, style: .continuous)
										.strokeBorder(.gray.opacity(0.3), lineWidth: 1)
								}
								.onTapGesture {
									_selectedScreenshotIndex = index
									_isScreenshotPreviewPresented = true
								}
						}
					}
				}
			}
			.padding(.horizontal)
			.compatScrollTargetLayout()
		}
		.compatScrollTargetBehavior()
		.padding(.horizontal, -16)
	}
}
