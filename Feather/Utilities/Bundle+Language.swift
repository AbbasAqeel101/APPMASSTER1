//
//  Bundle+Language.swift
//  AppMaster
//
//  Lets the user force the app's language to Arabic or English regardless
//  of the device's system language, via the Profile > Language screen.
//  Standard "swizzle Bundle.main" technique — works with strings compiled
//  from Localizable.xcstrings since Xcode still emits per-language
//  .lproj/Localizable.strings at build time.
//

import Foundation
import ObjectiveC

private var _appMasterBundleKey: UInt8 = 0

private final class AppMasterLanguageBundle: Bundle, @unchecked Sendable {
	override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
		guard
			let path = objc_getAssociatedObject(self, &_appMasterBundleKey) as? String,
			let bundle = Bundle(path: path)
		else {
			return super.localizedString(forKey: key, value: value, table: tableName)
		}
		return bundle.localizedString(forKey: key, value: value, table: tableName)
	}
}

extension Bundle {
	private static let storageKey = "AppMaster.appLanguage"

	/// Supported override languages. Add more here if AppMaster ever needs them —
	/// the Profile > Language screen only ever shows these two, by design.
	enum AppLanguage: String, CaseIterable, Identifiable {
		case arabic = "ar"
		case english = "en"

		var id: String { rawValue }

		var displayName: String {
			switch self {
			case .arabic: return "العربية"
			case .english: return "English"
			}
		}
	}

	/// The user's chosen language, or `nil` to follow the system language.
	static var appLanguageOverride: AppLanguage? {
		get {
			guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return nil }
			return AppLanguage(rawValue: raw)
		}
		set {
			UserDefaults.standard.set(newValue?.rawValue, forKey: storageKey)
			_applyLanguageOverride()
		}
	}

	/// Call once at app launch to apply a previously-saved override, if any.
	static func applyStoredLanguageOverrideIfNeeded() {
		_applyLanguageOverride()
	}

	private static func _applyLanguageOverride() {
		object_setClass(Bundle.main, AppMasterLanguageBundle.self)

		guard let language = appLanguageOverride else {
			objc_setAssociatedObject(Bundle.main, &_appMasterBundleKey, nil, .OBJC_ASSOCIATION_RETAIN)
			return
		}

		let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
			?? Bundle.main.path(forResource: "Base", ofType: "lproj")
		objc_setAssociatedObject(Bundle.main, &_appMasterBundleKey, path, .OBJC_ASSOCIATION_RETAIN)
	}
}
