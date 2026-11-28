//
//  CompanyCatalog.swift
//  AppMaster
//
//  Helpers shared by the Apps / Games / Search tabs. Everything here reads
//  the company catalog source (see FeatherApp._addCompanySource), so what you
//  add, move or rename on the dashboard shows up without a new build.
//
//  - An app's `category` (set on the dashboard) is the chip it appears under.
//  - A category whose name contains "games" / "game" / "ألعاب" / "العاب" /
//    "لعبة" is shown in the Games tab; every other category is in Apps.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews
import NukeUI

// MARK: - Entry
struct CatalogEntry: Identifiable {
	let sourceURL: URL?
	let repository: ASRepository
	let app: ASRepository.App

	var id: String { app.currentUniqueId }

	var category: String {
		(app.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

// MARK: - Catalog
enum CompanyCatalog {
	enum Kind {
		case apps
		case games
	}

	static func isGameCategory(_ name: String) -> Bool {
		let value = name.lowercased()
		let keywords: [String] = ["game", "ألعاب", "العاب", "لعبة", "لعبه"]
		for keyword in keywords {
			if value.contains(keyword) { return true }
		}
		return false
	}

	static func entries(sources: [AltSource], viewModel: SourcesViewModel) -> [CatalogEntry] {
		var company: [AltSource] = []
		for source in sources {
			if source.identifier == AppMasterConfig.companySourceIdentifier {
				company.append(source)
			}
		}
		let selected: [AltSource] = company.isEmpty ? sources : company

		var result: [CatalogEntry] = []
		for source in selected {
			guard let repository = viewModel.sources[source] else { continue }
			for app in repository.apps {
				result.append(CatalogEntry(sourceURL: source.sourceURL, repository: repository, app: app))
			}
		}
		return result
	}

	static func entries(of kind: Kind, from all: [CatalogEntry]) -> [CatalogEntry] {
		all.filter { entry in
			let isGame: Bool
			if let section = entry.app.section?.lowercased(), !section.isEmpty {
				isGame = section == "games"
			} else {
				isGame = isGameCategory(entry.category)
			}
			return kind == .games ? isGame : !isGame
		}
	}

	/// The tab's own main category ("تطبيقات" / "العاب"): it is the same as the "All" chip, so no chip is shown for it.
	static func isMainCategory(_ name: String, kind: Kind) -> Bool {
		let value = name
			.lowercased()
			.replacingOccurrences(of: "أ", with: "ا")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let main: [String] = kind == .games ? ["العاب", "games"] : ["تطبيقات", "apps"]
		return main.contains(value)
	}

	/// Every category of the tab, in the dashboard's order, even when it has no apps yet.
	static func categories(of kind: Kind, all: [CatalogEntry], tab: [CatalogEntry]) -> [String] {
		var result: [String] = []
		var seen = Set<String>()
		func add(_ name: String) {
			let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.isEmpty || seen.contains(trimmed) { return }
			if isMainCategory(trimmed, kind: kind) { return }
			seen.insert(trimmed)
			result.append(trimmed)
		}

		if let repository = all.first?.repository {
			let listed = kind == .games ? repository.gameCategories : repository.appCategories
			for name in listed ?? [] { add(name) }
		}
		// categories carried by the apps themselves (older feeds / other sources)
		for entry in tab { add(entry.category) }
		return result
	}
}

// MARK: - New update
extension ASRepository.App {
	/// Updated within the last 7 days.
	var isNewUpdate: Bool {
		guard let date = updateDate else { return false }
		let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
		return days < 7
	}
}

/// Green "New update" pill, shown beside the name for a week after an update.
struct NewUpdateBadge: View {
	var body: some View {
		Text(.localized("New Update"))
			.font(AppFont.caption2.weight(.bold))
			.foregroundStyle(Color.green)
			.lineLimit(1)
			.fixedSize()
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(Color.green.opacity(0.18))
			.clipShape(Capsule())
	}
}

// MARK: - Row
struct CatalogRowView: View {
	let entry: CatalogEntry

	var body: some View {
		NavigationLink {
			SourceAppsDetailView(
				sourceURL: entry.sourceURL,
				source: entry.repository,
				app: entry.app
			)
		} label: {
			HStack(spacing: 12) {
				_icon
				VStack(alignment: .leading, spacing: 3) {
					Text(entry.app.currentName)
						.font(AppFont.headline)
						.foregroundStyle(Color(uiColor: .label))
						.lineLimit(1)
					HStack(spacing: 6) {
						if entry.app.isNewUpdate { NewUpdateBadge() }
						Text(_subtitle)
							.font(AppFont.subheadline)
							.foregroundStyle(Color(uiColor: .secondaryLabel))
							.lineLimit(1)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				DownloadButtonView(
					sourceURL: entry.sourceURL,
					source: entry.repository,
					app: entry.app,
					compact: true,
					large: true
				)
			}
		}
	}

	@ViewBuilder
	private var _icon: some View {
		if let url = entry.app.iconURL {
			LazyImage(url: url) { state in
				if let image = state.image {
					image.appIconStyle(size: 58)
				} else {
					Image("App_Unknown").appIconStyle(size: 58)
				}
			}
		} else {
			Image("App_Unknown").appIconStyle(size: 58)
		}
	}

	/// A short line of the app's own description, with the version beside it.
	private var _subtitle: String {
		let raw = entry.app.localizedDescription ?? entry.app.description ?? entry.app.currentDescription ?? ""
		let description = raw
			.components(separatedBy: .newlines)
			.joined(separator: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		var text = ""
		if let version = entry.app.currentVersion, !version.isEmpty {
			text = isolatedLTR(version)
		}
		if !description.isEmpty {
			text += (text.isEmpty ? "" : "  ") + description
		}
		return text
	}
}

// MARK: - Category chips
struct CatalogChipsBar: View {
	let categories: [CategoryChip]
	@Binding var selection: String?

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				_chip(title: .localized("All"), isSelected: selection == nil) {
					selection = nil
				}

				ForEach(categories) { chip in
					_chip(title: chip.title, isSelected: selection == chip.key) {
						selection = chip.key
					}
				}
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
	}

	@ViewBuilder
	private func _chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Text(verbatim: title)
			.font(AppFont.subheadline.weight(.semibold))
			.lineLimit(1)
			.foregroundStyle(isSelected ? Color.white : Color(uiColor: .label))
			.padding(.horizontal, 16)
			.padding(.vertical, 9)
			.background(
				Capsule().fill(isSelected ? Color.accentColor : AppTheme.pill)
			)
			.contentShape(Capsule())
			.onTapGesture(perform: action)
			.accessibilityAddTraits(.isButton)
	}
}
