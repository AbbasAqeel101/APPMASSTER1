//
//  AppNotificationCenter.swift
//  AppMaster
//
//  In-app notification feed. The platform publishes notifications (title +
//  text) and this object downloads them from AppMasterConfig.notificationsURL,
//  keeps track of which ones the user has already seen, and exposes the unread
//  count that the bell button (and, when allowed, the app icon badge) shows.
//

import Foundation
import UIKit
import UserNotifications

// MARK: - Model
struct AppNotificationItem: Identifiable, Hashable {
	let id: String
	let title: String
	let body: String?
	let date: Date?
}

// MARK: - Center
final class AppNotificationCenter: ObservableObject {
	static let shared = AppNotificationCenter()

	@Published private(set) var items: [AppNotificationItem] = []
	@Published private(set) var unreadCount: Int = 0
	@Published private(set) var isLoading = false

	private let _seenKey = "AppMaster.seenNotificationIDs"

	static let authorizationStatusKey = "AppMaster.notificationAuthorizationStatus"

	/// Last known iOS notification permission, cached so Settings can show it instantly
	/// (no flash of the wrong state while the real status is being fetched).
	static var cachedAuthorizationStatus: UNAuthorizationStatus {
		UNAuthorizationStatus(rawValue: UserDefaults.standard.integer(forKey: authorizationStatusKey)) ?? .notDetermined
	}

	/// Shows the system Allow / Don't Allow prompt the first time only.
	@MainActor
	func requestAuthorizationIfNeeded() async {
		let center = UNUserNotificationCenter.current()
		var settings = await center.notificationSettings()

		if settings.authorizationStatus == .notDetermined {
			_ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
			settings = await center.notificationSettings()
		}

		UserDefaults.standard.set(settings.authorizationStatus.rawValue, forKey: Self.authorizationStatusKey)
		_updateUnread()
	}

	private var _seenIDs: Set<String> {
		get { Set(UserDefaults.standard.stringArray(forKey: _seenKey) ?? []) }
		set { UserDefaults.standard.set(Array(newValue), forKey: _seenKey) }
	}

	func isUnread(_ item: AppNotificationItem) -> Bool {
		!_seenIDs.contains(item.id)
	}

	@MainActor
	func markAllRead() {
		var seen = _seenIDs
		for item in items {
			seen.insert(item.id)
		}
		_seenIDs = seen
		_updateUnread()
	}

	@MainActor
	func refresh() async {
		guard let url = URL(string: AppMasterConfig.notificationsURL) else { return }

		isLoading = true
		defer { isLoading = false }

		do {
			var request = URLRequest(url: url)
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.timeoutInterval = 20

			let (data, _) = try await URLSession.shared.data(for: request)

			guard
				let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
				let rows = root["notifications"] as? [[String: Any]]
			else {
				return
			}

			var parsed: [AppNotificationItem] = []
			for row in rows {
				guard
					let id = row["id"] as? String,
					let title = row["title"] as? String
				else {
					continue
				}

				parsed.append(
					AppNotificationItem(
						id: id,
						title: title,
						body: row["body"] as? String,
						date: Self._parseDate(row["created_at"] as? String)
					)
				)
			}

			items = parsed
			_updateUnread()
		} catch {
			// offline / server error: keep whatever we already have
		}
	}

	@MainActor
	private func _updateUnread() {
		let seen = _seenIDs
		var count = 0
		for item in items {
			if !seen.contains(item.id) { count += 1 }
		}
		unreadCount = count
		UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
	}

	private static func _parseDate(_ string: String?) -> Date? {
		guard let string else { return nil }

		let withFraction = ISO8601DateFormatter()
		withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = withFraction.date(from: string) {
			return date
		}

		let plain = ISO8601DateFormatter()
		plain.formatOptions = [.withInternetDateTime]
		return plain.date(from: string)
	}
}
