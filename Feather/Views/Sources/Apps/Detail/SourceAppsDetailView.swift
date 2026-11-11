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
				_infoStrip()
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
	
	// MARK: Info strip (App Store style: swipe sideways to see all the cells)
	private var _isArabic: Bool {
		(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ar")
	}

	private func _t(_ ar: String, _ en: String) -> String { _isArabic ? ar : en }

	private struct InfoCellData: Identifiable {
		let id = UUID()
		let value: String
		let icon: String
	}

	private func _genreName(_ genre: String) -> String {
		guard _isArabic else { return genre }
		let map: [String: String] = [
			"Games": "ألعاب", "Social Networking": "تواصل اجتماعي", "Entertainment": "ترفيه",
			"Photo & Video": "تصوير وفيديو", "Music": "موسيقى", "Utilities": "أدوات",
			"Productivity": "إنتاجية", "Lifestyle": "أسلوب حياة", "Education": "تعليم",
			"News": "أخبار", "Sports": "رياضة", "Travel": "سفر", "Shopping": "تسوق",
			"Finance": "مال", "Health & Fitness": "صحة ولياقة", "Business": "أعمال",
			"Navigation": "خرائط", "Weather": "طقس", "Reference": "مراجع",
			"Food & Drink": "طعام وشراب", "Books": "كتب", "Medical": "طب",
			"Graphics & Design": "تصميم", "Developer Tools": "أدوات المطورين"
		]
		return map[genre] ?? genre
	}

	private func _infoCells() -> [InfoCellData] {
		var cells: [InfoCellData] = []

		// downloads
		let downloads = app.downloads ?? 0
		cells.append(InfoCellData(
			value: NumberFormatter.localizedString(from: NSNumber(value: downloads), number: .decimal),
			icon: "arrow.down.square"
		))

		// file size
		if let bytes = app.size ?? app.currentAppVersion?.size.map({ Int64($0) }), bytes > 0 {
			cells.append(InfoCellData(
				value: "~" + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
				icon: "shippingbox"
			))
		}

		// supported system
		if let minOS = app.currentAppVersion?.minOSVersion {
			cells.append(InfoCellData(value: "iOS \(minOS.description)+", icon: "iphone"))
		}

		// category
		let categoryName: String? = {
			if let genre = app.genre, !genre.isEmpty { return _genreName(genre) }
			if let category = app.category, !category.isEmpty { return category }
			return nil
		}()
		if let categoryName {
			cells.append(InfoCellData(value: categoryName, icon: "square.grid.2x2"))
		}

		// age
		if let age = app.ageRating, !age.isEmpty {
			let digits = age.filter(\.isNumber)
			cells.append(InfoCellData(value: digits.isEmpty ? age : "+" + digits, icon: "person.2"))
		}

		// rating
		if let rating = app.rating, rating > 0 {
			var text = String(format: "%.1f", rating)
			if let count = app.ratingCount, count > 0 {
				text += count >= 1000
					? " (" + String(format: "%.0f", Double(count) / 1000) + _t(" ألف", "K") + ")"
					: " (\(count))"
			}
			cells.append(InfoCellData(value: text, icon: "star.fill"))
		}

		return cells
	}

	@ViewBuilder
	private func _infoStrip() -> some View {
		let cells = _infoCells()
		if !cells.isEmpty {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 0) {
					ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
						_infoCell(cell)
						if index < cells.count - 1 {
							Divider().frame(height: 14)
						}
					}
				}
				.padding(.horizontal, 16)
			}
			.padding(.horizontal, -16)
		}
	}

	@ViewBuilder
	private func _infoCell(_ cell: InfoCellData) -> some View {
		HStack(spacing: 5) {
			Text(cell.value)
				.font(AppFont.caption)
				.lineLimit(1)
			Image(systemName: cell.icon)
				.font(.system(size: 11, weight: .regular))
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, 12)
		.padding(.vertical, 2)
	}

	/// "تحديث جديد" for the first week, then "قبل أسبوع" / "قبل أسبوعين" / "قبل 3 أسابيع", then months, then years.
	private func _updateLabel(_ date: Date) -> String {
		let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
		if days < 7 { return _t("تحديث جديد", "New update") }
		if days < 28 {
			let weeks = days / 7
			switch weeks {
			case 1: return _t("قبل أسبوع", "1 week ago")
			case 2: return _t("قبل أسبوعين", "2 weeks ago")
			default: return _t("قبل 3 أسابيع", "3 weeks ago")
			}
		}
		if days < 365 {
			let months = max(1, days / 30)
			switch months {
			case 1: return _t("قبل شهر", "1 month ago")
			case 2: return _t("قبل شهرين", "2 months ago")
			case 3...10: return _t("قبل \(months) أشهر", "\(months) months ago")
			default: return _t("قبل \(months) شهرًا", "\(months) months ago")
			}
		}
		let years = days / 365
		switch years {
		case 1: return _t("قبل سنة", "1 year ago")
		case 2: return _t("قبل سنتين", "2 years ago")
		case 3...10: return _t("قبل \(years) سنوات", "\(years) years ago")
		default: return _t("قبل \(years) سنة", "\(years) years ago")
		}
	}

	/// "Version 249.0 • 6 hours ago"
	@ViewBuilder
	private func _versionLine() -> some View {
		let parts = _versionParts()
		if !parts.isEmpty {
			Text(parts.joined(separator: "   "))
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
		if let date = app.updateDate {
			parts.append(_updateLabel(date))
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
