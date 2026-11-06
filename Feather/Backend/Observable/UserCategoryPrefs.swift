//
//  UserCategoryPrefs.swift
//  AppMaster
//
//  The person's own arrangement of the category chips in the Apps / Games tabs.
//  It is stored on the device only and never changes what other people see.
//

import SwiftUI

struct UserCategory: Codable, Identifiable, Hashable {
	var id: String
	var name: String
	var section: String      // "apps" | "games"
	var appKeys: [String]    // CatalogKey.of(app)
}

struct CategoryChip: Identifiable, Hashable {
	let key: String
	let title: String
	var id: String { key }
	var isCustom: Bool { key.hasPrefix("user:") }
}

private struct _Prefs: Codable {
	var order: [String: [String]] = [:]
	var hidden: [String] = []
	var renamed: [String: String] = [:]
	var custom: [UserCategory] = []
}

final class UserCategoryPrefs: ObservableObject {
	static let shared = UserCategoryPrefs()
	private static let _storeKey = "appmaster.userCategories"

	@Published private var _prefs: _Prefs

	private init() {
		if
			let data = UserDefaults.standard.data(forKey: Self._storeKey),
			let decoded = try? JSONDecoder().decode(_Prefs.self, from: data)
		{
			_prefs = decoded
		} else {
			_prefs = _Prefs()
		}
	}

	private func _save() {
		if let data = try? JSONEncoder().encode(_prefs) {
			UserDefaults.standard.set(data, forKey: Self._storeKey)
		}
	}

	private func _section(_ kind: CompanyCatalog.Kind) -> String {
		kind == .games ? "games" : "apps"
	}

	// MARK: Resolve

	/// Chips of a tab in the person's order. `base` = categories coming from the dashboard.
	func chips(for kind: CompanyCatalog.Kind, base: [String]) -> [CategoryChip] {
		let section = _section(kind)
		var all: [CategoryChip] = base.map { CategoryChip(key: $0, title: _prefs.renamed[$0] ?? $0) }
		for custom in _prefs.custom where custom.section == section {
			all.append(CategoryChip(key: custom.id, title: custom.name))
		}
		all = all.filter { !_prefs.hidden.contains($0.key) }

		let order = _prefs.order[section] ?? []
		var result: [CategoryChip] = []
		for key in order {
			if let chip = all.first(where: { $0.key == key }) { result.append(chip) }
		}
		for chip in all where !result.contains(where: { $0.key == chip.key }) {
			result.append(chip)
		}
		return result
	}

	func hiddenChips(for kind: CompanyCatalog.Kind, base: [String]) -> [CategoryChip] {
		base
			.filter { _prefs.hidden.contains($0) }
			.map { CategoryChip(key: $0, title: _prefs.renamed[$0] ?? $0) }
	}

	func appKeys(of key: String) -> [String] {
		_prefs.custom.first(where: { $0.id == key })?.appKeys ?? []
	}

	// MARK: Edit

	func saveOrder(_ chips: [CategoryChip], kind: CompanyCatalog.Kind) {
		_prefs.order[_section(kind)] = chips.map(\.key)
		_save()
	}

	func rename(key: String, to name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		if let index = _prefs.custom.firstIndex(where: { $0.id == key }) {
			_prefs.custom[index].name = trimmed
		} else {
			_prefs.renamed[key] = trimmed
		}
		_save()
	}

	func remove(key: String) {
		if let index = _prefs.custom.firstIndex(where: { $0.id == key }) {
			_prefs.custom.remove(at: index)
		} else if !_prefs.hidden.contains(key) {
			_prefs.hidden.append(key)
		}
		_save()
	}

	func restore(key: String) {
		_prefs.hidden.removeAll { $0 == key }
		_save()
	}

	@discardableResult
	func add(name: String, kind: CompanyCatalog.Kind) -> String? {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		let category = UserCategory(id: "user:\(UUID().uuidString)", name: trimmed, section: _section(kind), appKeys: [])
		_prefs.custom.append(category)
		_save()
		return category.id
	}

	func setApps(_ keys: [String], for key: String) {
		guard let index = _prefs.custom.firstIndex(where: { $0.id == key }) else { return }
		_prefs.custom[index].appKeys = keys
		_save()
	}

	func resetAll() {
		_prefs = _Prefs()
		_save()
	}
}
