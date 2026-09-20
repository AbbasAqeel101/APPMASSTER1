//
//  CatalogAppsView.swift
//  AppMaster
//
//  The "Apps" and "Games" tabs: category chips on top (managed from the
//  dashboard), the company apps below, the bell button on the leading side
//  and (Apps tab) the download button that opens the Library of downloaded
//  apps, where apps are signed, installed and imported.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct CatalogAppsView: View {
	let kind: CompanyCatalog.Kind

	@StateObject private var viewModel = SourcesViewModel.shared
	@State private var _selectedCategory: String?
	@State private var _isLibraryPresenting = false

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _title: String {
		kind == .games ? .localized("Games") : .localized("Apps")
	}

	private var _tabEntries: [CatalogEntry] {
		let all = CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
		return CompanyCatalog.entries(of: kind, from: all)
	}

	private func _visible(from entries: [CatalogEntry]) -> [CatalogEntry] {
		guard let selected = _selectedCategory else { return entries }
		return entries.filter { $0.category == selected }
	}

	// MARK: Body
	var body: some View {
		let entries = _tabEntries
		let categories = CompanyCatalog.categories(in: entries)
		let visible = _visible(from: entries)

		NBNavigationView(_title, displayMode: .inline) {
			VStack(spacing: 0) {
				if !categories.isEmpty {
					CatalogChipsBar(categories: categories, selection: $_selectedCategory)
				}

				List {
					ForEach(visible) { entry in
						CatalogRowView(entry: entry)
					}
				}
				.listStyle(.plain)
				.overlay {
					if visible.isEmpty {
						_placeholder()
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					NotificationBellButton()
				}
				if kind == .apps {
					ToolbarItem(placement: .topBarTrailing) {
						Button {
							_isLibraryPresenting = true
						} label: {
							Image(systemName: "arrow.down.circle")
						}
					}
				}
			}
			.sheet(isPresented: $_isLibraryPresenting) {
				LibraryView()
			}
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}

	@ViewBuilder
	private func _placeholder() -> some View {
		if viewModel.sources.isEmpty {
			ProgressView()
		} else {
			VStack(spacing: 8) {
				Image(systemName: "square.grid.2x2")
					.font(.system(size: 40))
					.foregroundStyle(.secondary)
				Text(.localized("No apps yet"))
					.font(.headline)
			}
		}
	}
}
