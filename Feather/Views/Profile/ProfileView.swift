//
//  ProfileView.swift
//  AppMaster
//
//  Presented as a sheet from the profile icon in HomeView's toolbar.
//
//  Layout: a header card (photo, name, subscription tier) followed by one
//  ordered list of rows, in the same style as Feather's Settings screen:
//
//    Profile · Certificates · Appearance · Notifications · About AppMaster
//    Features: Signing Options · Archive & Compression · Installation ·
//              Storage · Backup & Restore · Reset
//    Language · Help & Support
//
//  NOTE on subscription data: the tier is meant to come from the company
//  backend (the tier you assign on the dashboard). `_fetchSubscriptionStatus()`
//  below is still a stub for that call — swap its body once the endpoint
//  (Supabase Edge Function that checks this device's UDID) exists.
//

import SwiftUI
import NimbleViews

// MARK: - Model (stub, to be replaced by the real backend response)
struct AppMasterSubscriptionStatus {
	var tierName: String
	var isActive: Bool
}

// MARK: - Avatar
struct ProfileAvatarView: View {
	var size: CGFloat = 60

	// bumped whenever the photo changes so the view reloads it
	@AppStorage("AppMaster.profilePhotoVersion") private var _photoVersion: Int = 0

	var body: some View {
		Group {
			if let image = AppMasterProfile.loadPhoto() {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
			} else {
				Image(systemName: "person.crop.circle.fill")
					.resizable()
					.scaledToFit()
					.foregroundStyle(.secondary)
			}
		}
		.id(_photoVersion)
		.frame(width: size, height: size)
		.clipShape(Circle())
	}
}

// MARK: - Toolbar icon (Home)
/// Circle in Home's toolbar: the profile photo once one is set, otherwise the default person symbol.
struct ProfileToolbarIcon: View {
	@AppStorage("AppMaster.profilePhotoVersion") private var _photoVersion: Int = 0

	var body: some View {
		Group {
			if let image = AppMasterProfile.loadPhoto() {
				Image(uiImage: image)
					.renderingMode(.original)
					.resizable()
					.aspectRatio(contentMode: .fill)
			} else {
				Image(systemName: "person.crop.circle.fill")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.foregroundStyle(.secondary)
			}
		}
		.frame(width: 30, height: 30)
		.clipShape(Circle())
		.id(_photoVersion)
	}
}

// MARK: - View
struct ProfileView: View {
	@Environment(\.dismiss) private var dismiss

	@AppStorage("AppMaster.profileName") private var _profileName: String = ""

	@State private var _subscription: AppMasterSubscriptionStatus?
	@State private var _isLoadingSubscription = true

	private var _displayName: String {
		_profileName.isEmpty ? .localized("Guest") : _profileName
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Profile")) {
			Form {
				_header()
				_general()
				_features()
				_preferences()
			}
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Done")) { dismiss() }
				}
			}
		}
		.task {
			await _fetchSubscriptionStatus()
		}
	}
}

// MARK: - Sections
extension ProfileView {
	@ViewBuilder
	private func _header() -> some View {
		Section {
			HStack(spacing: 16) {
				ProfileAvatarView(size: 64)

				VStack(alignment: .leading, spacing: 4) {
					Text(_displayName)
						.font(.title3.bold())
					_subscriptionLabel()
				}

				Spacer(minLength: 0)
			}
			.padding(.vertical, 6)
		}
	}

	@ViewBuilder
	private func _subscriptionLabel() -> some View {
		if _isLoadingSubscription {
			HStack(spacing: 6) {
				ProgressView()
					.controlSize(.small)
				Text(.localized("Checking subscription…"))
					.foregroundStyle(.secondary)
			}
			.font(.subheadline)
		} else if let subscription = _subscription {
			HStack(spacing: 6) {
				Image(systemName: subscription.isActive ? "crown.fill" : "crown")
					.foregroundStyle(subscription.isActive ? .yellow : .secondary)
				Text(subscription.tierName)
			}
			.font(.subheadline)
		} else {
			Text(.localized("No active subscription"))
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func _general() -> some View {
		Section {
			NavigationLink(destination: EditProfileView()) {
				Label(.localized("Profile"), systemImage: "person.crop.circle")
			}
			NavigationLink(destination: CertificatesView()) {
				Label(.localized("Certificates"), systemImage: "checkmark.seal")
			}
			NavigationLink(destination: AppearanceView()) {
				Label(.localized("Appearance"), systemImage: "paintbrush")
			}
			NavigationLink(destination: NotificationsView()) {
				Label(.localized("Notifications"), systemImage: "bell.badge")
			}
			NavigationLink(destination: AboutView()) {
				Label {
					Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
				} icon: {
					Image("AppMasterGlyph")
						.renderingMode(.original)
						.appIconStyle(size: 30)
				}
			}
		}
	}

	@ViewBuilder
	private func _features() -> some View {
		NBSection(.localized("Features")) {
			NavigationLink(destination: ConfigurationView()) {
				Label(.localized("Signing Options"), systemImage: "signature")
			}
			NavigationLink(destination: ArchiveView()) {
				Label(.localized("Archive & Compression"), systemImage: "archivebox")
			}
			NavigationLink(destination: InstallationView()) {
				Label(.localized("Installation"), systemImage: "arrow.down.circle")
			}
			NavigationLink(destination: StorageView()) {
				Label(.localized("Storage"), systemImage: "internaldrive")
			}
			NavigationLink(destination: BackupRestoreView()) {
				Label(.localized("Backup & Restore"), systemImage: "arrow.triangle.2.circlepath")
			}
			NavigationLink(destination: ResetView()) {
				Label(.localized("Reset"), systemImage: "trash")
			}
		}
	}

	@ViewBuilder
	private func _preferences() -> some View {
		Section {
			NavigationLink(destination: LanguageView()) {
				Label(.localized("Language"), systemImage: "globe")
			}
			Button {
				UIApplication.open(AppMasterConfig.supportURL)
			} label: {
				Label(.localized("Help & Support"), systemImage: "questionmark.bubble")
			}
		}
	}
}

// MARK: - Actions
extension ProfileView {
	/// Stub — replace with a real call to the company backend once it exists
	/// (see file header for the intended flow).
	private func _fetchSubscriptionStatus() async {
		_isLoadingSubscription = true
		defer { _isLoadingSubscription = false }
		// TODO: call the company backend with this device's UDID and
		// map the response into `AppMasterSubscriptionStatus`.
		_subscription = nil
	}
}
