//
//  ProfileView.swift
//  AppMaster
//
//  Presented as a sheet from the profile icon in HomeView's toolbar.
//
//  NOTE on subscription/certificate data: this currently shows local
//  Feather certificate data only. Per the plan discussed, the
//  subscription tier + certificate status here should eventually come
//  from a new public Supabase Edge Function that:
//    1. receives this device's UDID
//    2. looks it up in the "الإشتراكات" (subscriptions) table already
//       used by the dashboard
//    3. if needed, checks/registers the certificate with api2.ipalinks.ru
//       server-side (the ipalinks API key must never ship in the app)
//    4. returns { tier, certificateStatus } to the app
//  `_fetchSubscriptionStatus()` below is a stub for that call — swap its
//  body once the endpoint exists.
//

import SwiftUI
import NimbleViews

// MARK: - Model (stub, to be replaced by the real backend response)
struct AppMasterSubscriptionStatus {
	var tierName: String
	var isActive: Bool
}

// MARK: - View
struct ProfileView: View {
	@Environment(\.dismiss) private var dismiss

	@AppStorage("AppMaster.profileName") private var _profileName: String = ""
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0

	@State private var _isEditProfilePresenting = false
	@State private var _subscription: AppMasterSubscriptionStatus?
	@State private var _isLoadingSubscription = true

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	private var _selectedCertificate: CertificatePair? {
		guard _storedSelectedCert >= 0, _storedSelectedCert < _certificates.count else { return nil }
		return _certificates[_storedSelectedCert]
	}

	private var _displayName: String {
		_profileName.isEmpty ? .localized("Guest") : _profileName
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Profile")) {
			Form {
				_header()
				_subscriptionSection()
				_certificateSection()
				_accountSection()
				_appSection()
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
				Image(systemName: "person.crop.circle.fill")
					.font(.system(size: 54))
					.foregroundStyle(.secondary)
				VStack(alignment: .leading, spacing: 4) {
					Text(_displayName)
						.font(.title3.bold())
					Text(.localized("Edit Profile"))
						.font(.footnote)
						.foregroundStyle(Color.accentColor)
				}
			}
			.contentShape(Rectangle())
			.onTapGesture { _isEditProfilePresenting = true }
		}
		.listRowBackground(EmptyView())
		.sheet(isPresented: $_isEditProfilePresenting) {
			EditProfileView(name: $_profileName)
		}
	}

	@ViewBuilder
	private func _subscriptionSection() -> some View {
		NBSection(.localized("Subscription")) {
			if _isLoadingSubscription {
				HStack {
					ProgressView()
					Text(.localized("Checking subscription…"))
						.foregroundStyle(.secondary)
				}
			} else if let subscription = _subscription {
				HStack {
					Image(systemName: subscription.isActive ? "crown.fill" : "crown")
						.foregroundStyle(subscription.isActive ? .yellow : .secondary)
					Text(subscription.tierName)
					Spacer()
					if subscription.isActive {
						Text(.localized("Active"))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			} else {
				Text(.localized("No active subscription"))
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private func _certificateSection() -> some View {
		NBSection(.localized("Certificates")) {
			if let cert = _selectedCertificate {
				CertificatesCellView(cert: cert)
			} else {
				Text(.localized("No Certificate"))
					.font(.footnote)
					.foregroundStyle(.secondary)
			}
			NavigationLink(destination: CertificatesView()) {
				Label(.localized("Manage Certificates"), systemImage: "checkmark.seal")
			}
		} footer: {
			Text(.localized("Add and manage the certificates used to sign and install apps on this device."))
		}
	}

	@ViewBuilder
	private func _accountSection() -> some View {
		NBSection(.localized("Account")) {
			Button {
				_isEditProfilePresenting = true
			} label: {
				Label(.localized("Edit Profile"), systemImage: "person.text.rectangle")
			}
		}
	}

	@ViewBuilder
	private func _appSection() -> some View {
		NBSection(.localized("App")) {
			NavigationLink(destination: LanguageView()) {
				Label(.localized("Language"), systemImage: "globe")
			}
			Button {
				_reportProblem()
			} label: {
				Label(.localized("Report a Problem"), systemImage: "exclamationmark.bubble")
			}
			NavigationLink {
				AboutView()
			} label: {
				Label {
					Text(verbatim: .localized("About %@", arguments: Bundle.main.name))
				} icon: {
					FRAppIconView(size: 23)
				}
			}
			NavigationLink(destination: SettingsView()) {
				Label(.localized("Advanced Settings"), systemImage: "gearshape.2")
			}
		}
	}
}

// MARK: - Actions
extension ProfileView {
	/// Stub — replace with a real call to the new Supabase Edge Function
	/// once it exists (see file header for the intended flow).
	private func _fetchSubscriptionStatus() async {
		_isLoadingSubscription = true
		defer { _isLoadingSubscription = false }
		// TODO: call the company backend with this device's UDID and
		// map the response into `AppMasterSubscriptionStatus`.
		_subscription = nil
	}

	private func _reportProblem() {
		// TODO: point this at AppMaster's real support channel/email.
		let supportEmail = "support@appmaster.example"
		let subject = "AppMaster \(Bundle.main.version) - Problem Report"
		if let url = URL(string: "mailto:\(supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
			UIApplication.open(url)
		}
	}
}
