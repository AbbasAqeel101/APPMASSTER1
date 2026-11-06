//
//  FavoritesStore.swift
//  AppMaster
//
//  The apps the person marked as favorites (stored on the device only).
//

import SwiftUI
import AltSourceKit

enum CatalogKey {
	/// Stable key of an app: stays the same when the app is updated to a new version/link.
	static func of(_ app: ASRepository.App) -> String {
		"\(app.id ?? "")|\(app.currentName)"
	}
}

final class FavoritesStore: ObservableObject {
	static let shared = FavoritesStore()

	private static let _storeKey = "appmaster.favorites"

	@Published private(set) var keys: [String]

	private init() {
		keys = UserDefaults.standard.stringArray(forKey: Self._storeKey) ?? []
	}

	func isFavorite(_ app: ASRepository.App) -> Bool {
		keys.contains(CatalogKey.of(app))
	}

	func toggle(_ app: ASRepository.App) {
		let key = CatalogKey.of(app)
		if let index = keys.firstIndex(of: key) {
			keys.remove(at: index)
		} else {
			keys.insert(key, at: 0)
		}
		_save()
	}

	func remove(key: String) {
		keys.removeAll { $0 == key }
		_save()
	}

	private func _save() {
		UserDefaults.standard.set(keys, forKey: Self._storeKey)
	}
}
