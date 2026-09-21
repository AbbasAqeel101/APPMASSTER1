//
//  AboutView.swift
//  AppMaster
//
//  Profile > About AppMaster: company icon, name, version, and the developer
//  card (photo, name, role) that opens the developer's Telegram account.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct AboutView: View {
	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			_header()
			_developer()
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _header() -> some View {
		Section {
			VStack(spacing: 10) {
				Image("AppMasterLogo")
					.appIconStyle(size: 76)
					.shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)

				Text(Bundle.main.name)
					.font(.largeTitle)
					.bold()
					.foregroundStyle(Color.accentColor)

				HStack(spacing: 4) {
					Text(.localized("Version"))
					Text(AppMasterConfig.displayVersion)
				}
				.font(.footnote)
				.foregroundStyle(.secondary)
			}
			.padding(.vertical, 12)
		}
		.frame(maxWidth: .infinity)
		.listRowBackground(EmptyView())
	}

	@ViewBuilder
	private func _developer() -> some View {
		NBSection(.localized("Developer")) {
			Button {
				UIApplication.open(AppMasterConfig.developerURL)
			} label: {
				HStack(spacing: 16) {
					Image("DeveloperPhoto")
						.resizable()
						.scaledToFill()
						.frame(width: 56, height: 56)
						.clipShape(Circle())

					VStack(alignment: .leading, spacing: 2) {
						Text(.localized("Developer Name"))
							.font(.headline)
							.foregroundStyle(.primary)
						Text(verbatim: "Developer")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}

					Spacer(minLength: 0)

					Image(systemName: "arrow.up.right")
						.foregroundColor(.secondary.opacity(0.65))
				}
				.padding(.vertical, 2)
			}
		}
	}
}
