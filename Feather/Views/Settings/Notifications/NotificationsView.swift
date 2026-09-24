//
//  NotificationsView.swift
//  AppMaster
//
//  Two screens share this view:
//   - .inbox    : opened from the bell button. Lists what was published from the
//                 platform; the unread number lives on the bell only.
//   - .settings : Profile > Notifications. Just the switch that allows iOS
//                 notifications, nothing else.
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
			NotificationsView(mode: .inbox)
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
	enum Mode {
		case inbox
		case settings
	}

	let mode: Mode

	@ObservedObject private var _center = AppNotificationCenter.shared
	@Environment(\.scenePhase) private var _scenePhase
	// Last known permission (cached) so the switch never flashes the wrong state
	// while the real status is being fetched.
	@State private var _status: UNAuthorizationStatus = AppNotificationCenter.cachedAuthorizationStatus

	init(mode: Mode = .inbox) {
		self.mode = mode
	}

	private var _isEnabled: Bool {
		guard _center.wantsNotifications else { return false }
		switch _status {
		case .authorized, .provisional, .ephemeral:
			return true
		default:
			return false
		}
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Notifications")) {
			if mode == .settings {
				_permission()
			} else {
				_inbox()
			}
		}
		.overlay {
			if mode == .inbox && _center.items.isEmpty && !_center.isLoading {
				Text(.localized("No notifications yet"))
					.foregroundStyle(.secondary)
					.padding(.top, 120)
			}
		}
		.refreshable {
			if mode == .inbox {
				await _center.refresh()
			}
		}
		.task {
			if mode == .inbox {
				await _center.refresh()
			}
			await _refreshStatus()
		}
		.onDisappear {
			// only opening the inbox counts as reading the notifications
			if mode == .inbox {
				Task { @MainActor in
					_center.markAllRead()
				}
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
			Toggle(isOn: _enabledBinding) {
				Label(.localized("Alerts & Badge"), systemImage: "bell.badge")
			}
		} footer: {
			Text(.localized("Enable notifications to receive updates"))
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
	private var _enabledBinding: Binding<Bool> {
		Binding(
			get: { _isEnabled },
			set: { wantsOn in
				// turning OFF is always our own choice — never needs system Settings
				guard wantsOn else {
					Task { @MainActor in _center.setWantsNotifications(false) }
					return
				}

				switch _status {
				case .notDetermined:
					_request()
				case .authorized, .provisional, .ephemeral:
					// iOS permission is already granted, so just turn our own switch back on
					Task { @MainActor in _center.setWantsNotifications(true) }
				default:
					// denied: only the person can undo that from system Settings, iOS gives no other way
					_openSettings()
				}
			}
		)
	}

	private func _refreshStatus() async {
		let settings = await UNUserNotificationCenter.current().notificationSettings()
		_status = settings.authorizationStatus
		UserDefaults.standard.set(settings.authorizationStatus.rawValue, forKey: AppNotificationCenter.authorizationStatusKey)
	}

	private func _request() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
			Task {
				await _refreshStatus()
				if granted {
					await _center.setWantsNotifications(true)
				}
			}
		}
	}

	private func _openSettings() {
		if let url = URL(string: UIApplication.openSettingsURLString) {
			UIApplication.open(url)
		}
	}
}
