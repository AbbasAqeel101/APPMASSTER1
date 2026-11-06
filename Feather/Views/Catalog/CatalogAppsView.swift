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
	@ObservedObject private var _prefs = UserCategoryPrefs.shared
	@State private var _selectedCategory: String?
	@State private var _isLibraryPresenting = false
	@State private var _limit = 60

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _title: String {
		kind == .games ? .localized("Games") : .localized("Apps")
	}

	private var _allEntries: [CatalogEntry] {
		CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
	}

	private func _visible(from entries: [CatalogEntry], selected: String?) -> [CatalogEntry] {
		guard let selected else { return entries }
		if selected.hasPrefix("user:") {
			let keys = Set(_prefs.appKeys(of: selected))
			return entries.filter { keys.contains(CatalogKey.of($0.app)) }
		}
		return entries.filter { $0.category == selected }
	}

	/// A chip the person just hid/removed must not stay selected.
	private func _validSelection(_ categories: [CategoryChip]) -> String? {
		guard let selected = _selectedCategory else { return nil }
		return categories.contains(where: { $0.key == selected }) ? selected : nil
	}

	// MARK: Body
	var body: some View {
		let all = _allEntries
		let entries = CompanyCatalog.entries(of: kind, from: all)
		let baseCategories = CompanyCatalog.categories(of: kind, all: all, tab: entries)
		let categories = _prefs.chips(for: kind, base: baseCategories)
		let visible = _visible(from: entries, selected: _validSelection(categories))

		NBNavigationView(_title, displayMode: .inline) {
			List {
				CatalogChipsBar(categories: categories, selection: $_selectedCategory)
					.listRowInsets(EdgeInsets())
					.listRowSeparator(.hidden)
					.listRowBackground(Color.clear)

				ForEach(visible.prefix(_limit)) { entry in
					CatalogRowView(entry: entry)
				}
				if visible.count > _limit {
					Color.clear
						.frame(height: 1)
						.listRowSeparator(.hidden)
						.onAppear { _limit += 60 }
				}
			}
			.onChange(of: _selectedCategory) { _ in _limit = 60 }
			.listStyle(.plain)
			.overlay {
				if visible.isEmpty {
					_placeholder()
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
				Text(.localized(_selectedCategory == nil ? "No apps yet" : "No apps in this category"))
					.font(.headline)
			}
		}
	}
}
