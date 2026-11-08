//
//  CustomizeInterfaceView.swift
//  AppMaster
//
//  The person's own categories for the Apps / Games tabs: reorder, rename,
//  remove or add. Only visible on this device.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews

struct CustomizeInterfaceView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@ObservedObject private var _prefs = UserCategoryPrefs.shared

	@State private var _kind: CompanyCatalog.Kind = .apps
	@State private var _isAdding = false
	@State private var _newName = ""
	@State private var _renameKey: String?
	@State private var _renameText = ""
	@State private var _editMode: EditMode = .inactive

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _all: [CatalogEntry] {
		CompanyCatalog.entries(sources: Array(_sources), viewModel: viewModel)
	}

	private var _base: [String] {
		let all = _all
		return CompanyCatalog.categories(of: _kind, all: all, tab: CompanyCatalog.entries(of: _kind, from: all))
	}

	var body: some View {
		let chips = _prefs.chips(for: _kind, base: _base)
		let hidden = _prefs.hiddenChips(for: _kind, base: _base)

		List {
			Section {
				Picker("", selection: $_kind) {
					Text(.localized("Apps")).tag(CompanyCatalog.Kind.apps)
					Text(.localized("Games")).tag(CompanyCatalog.Kind.games)
				}
				.pickerStyle(.segmented)
				.listRowBackground(Color.clear)
			}
			.appRowBackground()

			Section {
				ForEach(chips) { chip in
					_row(chip)
				}
				.onMove { source, destination in
					var moved = chips
					moved.move(fromOffsets: source, toOffset: destination)
					_prefs.saveOrder(moved, kind: _kind)
				}
				.onDelete { offsets in
					for index in offsets { _prefs.remove(key: chips[index].key) }
				}
			}
			.appRowBackground()

			if !hidden.isEmpty {
				Section(header: Text(.localized("Hidden"))) {
					ForEach(hidden) { chip in
						HStack {
							Text(verbatim: chip.title)
							Spacer()
							Button(.localized("Restore")) { _prefs.restore(key: chip.key) }
						}
					}
				}
				.appRowBackground()
			}

			Section {
				Button(role: .destructive) {
					_prefs.resetAll()
				} label: {
					Text(.localized("Reset"))
				}
			}
			.appRowBackground()
		}
		.environment(\.editMode, $_editMode)
		.navigationTitle(.localized("Customize Interface"))
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					_newName = ""
					_isAdding = true
				} label: {
					Image(systemName: "plus")
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button(_editMode == .active ? String.localized("Done") : String.localized("Edit")) {
					withAnimation { _editMode = _editMode == .active ? .inactive : .active }
				}
			}
		}
		.alert(.localized("New Category"), isPresented: $_isAdding) {
			TextField(.localized("Name"), text: $_newName)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Add")) { _prefs.add(name: _newName, kind: _kind) }
		}
		.alert(.localized("Rename"), isPresented: Binding(get: { _renameKey != nil }, set: { if !$0 { _renameKey = nil } })) {
			TextField(.localized("Name"), text: $_renameText)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("OK")) {
				if let key = _renameKey { _prefs.rename(key: key, to: _renameText) }
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}

	@ViewBuilder
	private func _row(_ chip: CategoryChip) -> some View {
		HStack {
			if chip.isCustom {
				NavigationLink {
					CustomCategoryAppsView(key: chip.key, kind: _kind, entries: CompanyCatalog.entries(of: _kind, from: _all))
				} label: {
					Text(verbatim: chip.title)
				}
			} else {
				Text(verbatim: chip.title)
			}
			Spacer(minLength: 0)
			Button {
				_renameText = chip.title
				_renameKey = chip.key
			} label: {
				Image(systemName: "pencil")
			}
			.buttonStyle(.borderless)
		}
	}
}

// MARK: - Apps of a custom category
struct CustomCategoryAppsView: View {
	let key: String
	let kind: CompanyCatalog.Kind
	let entries: [CatalogEntry]

	@ObservedObject private var _prefs = UserCategoryPrefs.shared
	@State private var _search = ""

	var body: some View {
		let selected = Set(_prefs.appKeys(of: key))
		let shown = _search.isEmpty
			? entries
			: entries.filter { $0.app.currentName.localizedCaseInsensitiveContains(_search) }

		List {
			ForEach(shown.prefix(200)) { entry in
				let appKey = CatalogKey.of(entry.app)
				Button {
					var keys = selected
					if keys.contains(appKey) { keys.remove(appKey) } else { keys.insert(appKey) }
					_prefs.setApps(Array(keys), for: key)
				} label: {
					HStack {
						FRIconCellView(title: entry.app.currentName, subtitle: entry.app.currentVersion ?? "", iconUrl: entry.app.iconURL)
						Spacer()
						if selected.contains(appKey) {
							Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
						}
					}
				}
				.buttonStyle(.plain)
			}
		}
		.listStyle(.plain)
		.searchable(text: $_search)
		.navigationTitle(.localized("Apps"))
	}
}
