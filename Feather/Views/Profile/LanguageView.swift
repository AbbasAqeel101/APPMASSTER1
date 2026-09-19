//
//  LanguageView.swift
//  AppMaster
//
//  Lets the user pick Arabic or English for the app's UI, independent of
//  the device's system language. Selecting a language relaunches the UI
//  by asking the user to restart, since Bundle overrides only take full
//  effect for strings resolved after the override is applied.
//

import SwiftUI
import NimbleViews

struct LanguageView: View {
	@State private var _selected: Bundle.AppLanguage? = Bundle.appLanguageOverride
	@State private var _isRestartAlertPresented = false

	var body: some View {
		NBList(.localized("Language")) {
			Section {
				ForEach(Bundle.AppLanguage.allCases) { language in
					Button {
						guard language != _selected else { return }
						_selected = language
						Bundle.appLanguageOverride = language
						_isRestartAlertPresented = true
					} label: {
						HStack {
							Text(language.displayName)
								.foregroundStyle(.primary)
							Spacer()
							if _selected == language {
								Image(systemName: "checkmark")
									.foregroundStyle(Color.accentColor)
							}
						}
					}
				}
			} footer: {
				Text(.localized("Restart the app for the language change to fully apply everywhere."))
			}
		}
		.alert(.localized("Language Changed"), isPresented: $_isRestartAlertPresented) {
			Button(.localized("OK"), role: .cancel) { }
		} message: {
			Text(.localized("Please restart AppMaster for the new language to fully apply."))
		}
	}
}
