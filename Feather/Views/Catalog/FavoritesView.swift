//
//  FavoritesView.swift
//  AppMaster
//
//  The apps the person added to favorites (from the "…" menu of an app).
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct FavoritesView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@ObservedObject private var _favorites = FavoritesStore.shared

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _entries: [CatalogEntry] {
		let all = CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
		var result: [CatalogEntry] = []
		for key in _favorites.keys {
			if let entry = all.first(where: { CatalogKey.of($0.app) == key }) {
				result.append(entry)
			}
		}
		return result
	}

	var body: some View {
		let entries = _entries
		List {
			ForEach(entries) { entry in
				CatalogRowView(entry: entry)
			}
			.onDelete { offsets in
				for index in offsets {
					_favorites.remove(key: CatalogKey.of(entries[index].app))
				}
			}
		}
		.listStyle(.plain)
		.navigationTitle(.localized("Favorites"))
		.overlay {
			if entries.isEmpty {
				Image(systemName: "star")
					.font(.system(size: 40))
					.foregroundStyle(.secondary)
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}
