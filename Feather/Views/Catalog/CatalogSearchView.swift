//
//  CatalogSearchView.swift
//  AppMaster
//
//  The search tab (the separate search button on the trailing edge of the
//  tab bar): searches every app and game of the company catalog.
//  The searchable text is normalized once in the background and the query is
//  matched after a short pause, so typing stays smooth.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct CatalogSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@State private var _searchText = ""
	@State private var _limit = 60
	@State private var _items: [CatalogSearchItem] = []
	@State private var _results: [CatalogEntry] = []

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private struct _SearchKey: Hashable {
		let text: String
		let count: Int
	}

	// MARK: Body
	var body: some View {
		NavigationStack {
			List {
				ForEach(_results.prefix(_limit)) { entry in
					CatalogRowView(entry: entry)
				}
				if _results.count > _limit {
					Color.clear
						.frame(height: 1)
						.listRowSeparator(.hidden)
						.onAppear { _limit += 60 }
				}
			}
			.listStyle(.plain)
			.navigationTitle(.localized("Search"))
			.searchable(text: $_searchText, prompt: Text(.localized("Apps and games")))
			.overlay {
				if _results.isEmpty {
					if viewModel.sources.isEmpty || _items.isEmpty {
						ProgressView()
					} else {
						Text(.localized("No Results"))
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
		.task(id: viewModel.sources.count) {
			let entries = CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
			let built = await Task.detached(priority: .userInitiated) {
				CatalogSearchIndex.build(from: entries)
			}.value
			_items = built
		}
		.task(id: _SearchKey(text: _searchText, count: _items.count)) {
			if !_searchText.isEmpty {
				try? await Task.sleep(nanoseconds: 250_000_000)
				if Task.isCancelled { return }
			}
			let query = _searchText
			let items = _items
			let found = await Task.detached(priority: .userInitiated) {
				CatalogSearchIndex.search(query, in: items)
			}.value
			if Task.isCancelled { return }
			_results = found
			_limit = 60
		}
	}
}
