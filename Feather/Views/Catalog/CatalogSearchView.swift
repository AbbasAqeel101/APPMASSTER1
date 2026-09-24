//
//  CatalogSearchView.swift
//  AppMaster
//
//  The search tab (the separate search button on the trailing edge of the
//  tab bar): searches every app and game of the company catalog.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct CatalogSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@State private var _searchText = ""

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _results: [CatalogEntry] {
		let all = CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
		let query = CatalogSearchMatching.normalize(_searchText)
		if query.isEmpty { return all }

		return all.filter { entry in
			if CatalogSearchMatching.fuzzyContains(query: query, in: CatalogSearchMatching.normalize(entry.app.currentName)) {
				return true
			}
			if CatalogSearchMatching.fuzzyContains(query: query, in: CatalogSearchMatching.normalize(entry.category)) {
				return true
			}
			if let text = entry.app.currentDescription,
			   CatalogSearchMatching.fuzzyContains(query: query, in: CatalogSearchMatching.normalize(text)) {
				return true
			}
			if CatalogSearchMatching.matchesSynonym(query: query, appName: entry.app.currentName) {
				return true
			}
			return false
		}
	}

	// MARK: Body
	var body: some View {
		let results = _results

		NavigationStack {
			List {
				ForEach(results) { entry in
					CatalogRowView(entry: entry)
				}
			}
			.listStyle(.plain)
			.navigationTitle(.localized("Search"))
			.searchable(text: $_searchText, prompt: Text(.localized("Apps and games")))
			.overlay {
				if results.isEmpty {
					if viewModel.sources.isEmpty {
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
	}
}
