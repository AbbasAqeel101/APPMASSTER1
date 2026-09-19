//
//  EditProfileView.swift
//  AppMaster
//
//  Local-only for now: stores the display name in UserDefaults. Once the
//  Profile screen is wired to the company backend, this should instead
//  read/write the account record tied to the device's UDID.
//

import SwiftUI
import NimbleViews

struct EditProfileView: View {
	@Environment(\.dismiss) private var dismiss
	@Binding var name: String

	@State private var _draftName: String = ""

	var body: some View {
		NBNavigationView(.localized("Edit Profile")) {
			Form {
				Section(.localized("Name")) {
					TextField(.localized("Name"), text: $_draftName)
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(.localized("Cancel")) { dismiss() }
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Save")) {
						name = _draftName.trimmingCharacters(in: .whitespacesAndNewlines)
						dismiss()
					}
					.bold()
				}
			}
		}
		.onAppear { _draftName = name }
	}
}
