//
//  NotificationsView.swift
//  AppMaster
//
//  Notifications inbox (opened from the bell button and from Profile >
//  Notifications). Lists what was published from the platform, with a small
//  section to allow iOS notifications / the app icon badge.
//

import SwiftUI
import UserNotifications
import NimbleViews

// MARK: - Bell button (used in the toolbars of Home / Apps / Games)
struct NotificationBellButton: View {
	@ObservedObject private var _center = AppNotificationCenter.shared
	@State private var _isPresenting = false

	var body: some View {
		Button {
			_isPresenting = true
		} label: {
			Image(systemName: "bell")
				.overlay(alignment: .topTrailing) {
					if _center.unreadCount > 0 {
						Text(_center.unreadCount > 99 ? "99+" : "\(_center.unreadCount)")
							.font(.system(size: 10, weight: .bold))
							.foregroundStyle(.white)
							.padding(.horizontal, 5)
							.padding(.vertical, 1)
							.background(Capsule().fill(Color.red))
							.offset(x: 10, y: -8)
					}
				}
		}
		.task {
			await _center.refresh()
		}
		.sheet(isPresented: $_isPresenting) {
			NotificationsSheetView()
		}
	}
}

struct NotificationsSheetView: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NBNavigationView(.localized("Notifications")) {
			NotificationsView()
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						Button(.localized("Done")) { dismiss() }
					}
				}
		}
	}
}

// MARK: - View
struct NotificationsView: View {
	@ObservedObject private var _center = AppNotificationCenter.shared
	@Environment(\.scenePhase) private var _scenePhase
	@State private var _status: UNAuthorizationStatus = .notDetermined

	private var _statusText: String {
		switch _status {
		case .authorized, .provisional, .ephemeral:
			return .localized("Enabled")
		case .denied:
			return .localized("Disabled")
		default:
			return .localized("Not enabled yet")
		}
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Notifications")) {
			_permission()
			_inbox()
		}
		.overlay {
			if _center.items.isEmpty && !_center.isLoading {
				Text(.localized("No notifications yet"))
					.foregroundStyle(.secondary)
					.padding(.top, 120)
			}
		}
		.refreshable {
			await _center.refresh()
		}
		.task {
			await _center.refresh()
			await _refreshStatus()
		}
		.onDisappear {
			Task { @MainActor in
				_center.markAllRead()
			}
		}
		.onChange(of: _scenePhase) { phase in
			if phase == .active {
				Task { await _refreshStatus() }
			}
		}
	}
}

// MARK: - Sections
extension NotificationsView {
	@ViewBuilder
	private func _permission() -> some View {
		Section {
			HStack {
				Label(.localized("Alerts & Badge"), systemImage: "bell.badge")
				Spacer()
				Text(_statusText)
					.foregroundStyle(.secondary)
			}

			if _status == .notDetermined {
				Button(.localized("Enable Notifications")) {
					_request()
				}
			} else if _status == .denied {
				Button(.localized("Open iOS Settings")) {
					_openSettings()
				}
			}
		} footer: {
			Text(.localized("New notifications from AppMaster appear here and as a number on the app icon."))
		}
	}

	@ViewBuilder
	private func _inbox() -> some View {
		Section {
			ForEach(_center.items) { item in
				_row(item)
			}
		}
	}

	@ViewBuilder
	private func _row(_ item: AppNotificationItem) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Circle()
				.fill(_center.isUnread(item) ? Color.accentColor : Color.clear)
				.frame(width: 9, height: 9)
				.padding(.top, 6)

			VStack(alignment: .leading, spacing: 4) {
				Text(item.title)
					.font(.headline)

				if let body = item.body, !body.isEmpty {
					Text(body)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				if let date = item.date {
					Text(date, style: .relative)
						.font(.caption)
						.foregroundStyle(.tertiary)
				}
			}
		}
		.padding(.vertical, 2)
	}
}

// MARK: - Actions
extension NotificationsView {
	private func _refreshStatus() async {
		let settings = await UNUserNotificationCenter.current().notificationSettings()
		_status = settings.authorizationStatus
	}

	private func _request() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
			Task { await _refreshStatus() }
		}
	}

	private func _openSettings() {
		if let url = URL(string: UIApplication.openSettingsURLString) {
			UIApplication.open(url)
		}
	}
}
