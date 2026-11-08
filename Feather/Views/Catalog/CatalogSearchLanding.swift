//
//  CatalogSearchLanding.swift
//  AppMaster
//
//  What the Search tab shows before anything is typed, like the App Store:
//  a few suggested apps and "Browse" tiles (most downloaded apps / games and
//  the categories added on the dashboard, e.g. football or movies).
//

import SwiftUI
import AltSourceKit
import NimbleViews

struct CatalogSearchLanding: View {
	let entries: [CatalogEntry]

	private struct _Tile: Identifiable {
		let id: String
		let title: String
		let symbol: String
		let colors: [Color]
		let entries: [CatalogEntry]
	}

	private static let _palette: [[Color]] = [
		[Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.20, green: 0.42, blue: 0.85)],
		[Color(red: 1.00, green: 0.62, blue: 0.30), Color(red: 0.92, green: 0.40, blue: 0.20)],
		[Color(red: 0.40, green: 0.80, blue: 0.50), Color(red: 0.20, green: 0.62, blue: 0.38)],
		[Color(red: 0.62, green: 0.50, blue: 0.98), Color(red: 0.42, green: 0.32, blue: 0.85)],
		[Color(red: 0.98, green: 0.45, blue: 0.62), Color(red: 0.85, green: 0.25, blue: 0.45)],
		[Color(red: 0.30, green: 0.78, blue: 0.82), Color(red: 0.15, green: 0.55, blue: 0.65)]
	]

	private func _byDownloads(_ list: [CatalogEntry]) -> [CatalogEntry] {
		list.enumerated()
			.sorted { lhs, rhs in
				let l = lhs.element.app.downloads ?? 0
				let r = rhs.element.app.downloads ?? 0
				return l != r ? l > r : lhs.offset < rhs.offset
			}
			.map(\.element)
	}

	private var _suggestions: [CatalogEntry] {
		var result: [CatalogEntry] = []
		if let featured = entries.first?.repository.featuredApps, !featured.isEmpty {
			for id in featured {
				if let entry = entries.first(where: { $0.app.id == id }) { result.append(entry) }
			}
		}
		if result.isEmpty { result = _byDownloads(entries) }
		return Array(result.prefix(5))
	}

	private var _tiles: [_Tile] {
		var tiles: [_Tile] = []
		let apps = CompanyCatalog.entries(of: .apps, from: entries)
		let games = CompanyCatalog.entries(of: .games, from: entries)
		tiles.append(_Tile(id: "top-apps", title: .localized("Most Downloaded Apps"), symbol: "star.fill",
			colors: Self._palette[0], entries: _byDownloads(apps)))
		tiles.append(_Tile(id: "top-games", title: .localized("Most Downloaded Games"), symbol: "gamecontroller.fill",
			colors: Self._palette[1], entries: _byDownloads(games)))

		// categories added on the dashboard (football, movies ...)
		var index = 2
		for kind in [CompanyCatalog.Kind.apps, CompanyCatalog.Kind.games] {
			let tab = kind == .apps ? apps : games
			for name in CompanyCatalog.categories(of: kind, all: entries, tab: tab) {
				let list = tab.filter { $0.category == name }
				tiles.append(_Tile(id: "cat-\(name)", title: name, symbol: "square.grid.2x2.fill",
					colors: Self._palette[index % Self._palette.count], entries: _byDownloads(list)))
				index += 1
			}
		}
		return tiles
	}

	var body: some View {
		ScrollView {
			if entries.isEmpty {
				ProgressView().padding(.top, 80)
			} else {
				VStack(alignment: .leading, spacing: 24) {
					_suggestionsSection()
					_browseSection()
				}
				.padding(.vertical, 12)
			}
		}
	}

	@ViewBuilder
	private func _suggestionsSection() -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(.localized("Suggestions"))
				.font(AppFont.title2.bold())
				.padding(.horizontal)
			VStack(spacing: 0) {
				ForEach(_suggestions) { entry in
					CatalogRowView(entry: entry)
						.padding(.horizontal)
						.padding(.vertical, 6)
					Divider().padding(.leading, 76)
				}
			}
		}
	}

	@ViewBuilder
	private func _browseSection() -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(.localized("Browse"))
				.font(AppFont.title2.bold())
				.padding(.horizontal)
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
				ForEach(_tiles) { tile in
					NavigationLink {
						CatalogEntriesListView(title: tile.title, entries: tile.entries)
					} label: {
						_tileView(tile)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal)
		}
	}

	@ViewBuilder
	private func _tileView(_ tile: _Tile) -> some View {
		ZStack(alignment: .bottomLeading) {
			LinearGradient(colors: tile.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
			Image(systemName: tile.symbol)
				.font(.system(size: 44))
				.foregroundStyle(.white.opacity(0.35))
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
				.padding(12)
			Text(verbatim: tile.title)
				.font(AppFont.headline.bold())
				.foregroundStyle(.white)
				.multilineTextAlignment(.leading)
				.lineLimit(3)
				.padding(12)
		}
		.frame(height: 120)
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
}

// MARK: - A tile's apps
struct CatalogEntriesListView: View {
	let title: String
	let entries: [CatalogEntry]
	@State private var _limit = 60

	var body: some View {
		List {
			ForEach(entries.prefix(_limit)) { entry in
				CatalogRowView(entry: entry)
			}
			if entries.count > _limit {
				Color.clear
					.frame(height: 1)
					.listRowSeparator(.hidden)
					.onAppear { _limit += 60 }
			}
		}
		.listStyle(.plain)
		.navigationTitle(title)
		.navigationBarTitleDisplayMode(.inline)
		.overlay {
			if entries.isEmpty {
				Text(.localized("No apps in this category"))
					.foregroundStyle(.secondary)
			}
		}
	}
}
