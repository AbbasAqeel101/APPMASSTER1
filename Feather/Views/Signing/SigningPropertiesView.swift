//
//  SigningAppPropertiesView.swift
//  Feather
//
//  Created by samara on 17.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningPropertiesView: View {
	@Environment(\.dismiss) var dismiss
	
	@State private var text: String = ""
	
	var saveButtonDisabled: Bool {
		text == initialValue
	}
	
	var title: String
	var initialValue: String 
	@Binding var bindingValue: String?
	/// App identifier found in the selected certificate's provisioning profile
	/// (the value right after the team ID in `application-identifier`). When set,
	/// a "Match Certificate Identifier" row is shown under the text field.
	var certificateIdentifier: String? = nil
	
	// MARK: Body
	var body: some View {
		NBList(title) {
			Section {
				TextField(initialValue, text: $text)
					.textInputAutocapitalization(.none)
			}
			
			if let certificateIdentifier {
				Section {
					Button {
						text = certificateIdentifier
					} label: {
						Label(String.localized("Match Certificate Identifier"), systemImage: "checkmark.seal")
					}
				} footer: {
					Text(String.localized("Use %@ from the selected provisioning profile.", arguments: certificateIdentifier))
				}
			}
		}
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .topBarTrailing,
				isDisabled: saveButtonDisabled
			) {
				if !saveButtonDisabled {
					bindingValue = text
					dismiss()
				}
			}
		}
		.onAppear {
			text = initialValue
		}
	}
}
