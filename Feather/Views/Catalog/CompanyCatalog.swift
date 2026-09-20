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
			let isGame = isGameCategory(entry.category)
			return kind == .games ? isGame : !isGame
		}
	}

	/// Distinct, non-empty categories in the order the catalog lists them.
	static func categories(in entries: [CatalogEntry]) -> [String] {
		var seen = Set<String>()
		var ordered: [String] = []
		for entry in entries {
			let name = entry.category
			if name.isEmpty || seen.contains(name) { continue }
			seen.insert(name)
			ordered.append(name)
		}
		return ordered
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
			HStack(spacing: 2) {
				FRIconCellView(
					title: entry.app.currentName,
					subtitle: _subtitle,
					iconUrl: entry.app.iconURL
				)
				DownloadButtonView(
					sourceURL: entry.sourceURL,
					source: entry.repository,
					app: entry.app
				)
			}
		}
	}

	private var _subtitle: String {
		var parts: [String] = []
		if let version = entry.app.currentVersion, !version.isEmpty {
			parts.append(version)
		}
		if !entry.category.isEmpty {
			parts.append(entry.category)
		}
		return parts.joined(separator: " • ")
	}
}

// MARK: - Category chips
struct CatalogChipsBar: View {
	let categories: [String]
	@Binding var selection: String?

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				_chip(title: .localized("All"), isSelected: selection == nil) {
					selection = nil
				}

				ForEach(categories, id: \.self) { name in
					_chip(title: name, isSelected: selection == name) {
						selection = name
					}
				}
			}
			.padding(.horizontal)
			.padding(.vertical, 6)
		}
	}

	@ViewBuilder
	private func _chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
				.font(.subheadline.weight(.semibold))
				.lineLimit(1)
				.foregroundStyle(isSelected ? Color.white : Color.primary)
				.padding(.horizontal, 16)
				.padding(.vertical, 9)
				.background(
					Capsule().fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill))
				)
		}
		.buttonStyle(.plain)
	}
}
