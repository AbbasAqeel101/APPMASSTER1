//
//  AppTheme.swift
//  AppMaster
//
//  App-wide look: system font (SF Pro) with IBM Plex Sans Arabic as the Arabic
//  cascade fallback, and the solid black backgrounds.
//
//  The font files (.ttf / .otf) are picked up automatically from anywhere inside
//  the app bundle (put them in Feather/Resources/Fonts). Until they are added the
//  system font is used, so nothing breaks.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Font
/// The system font (SF Pro) is the base font of the whole app, so Latin letters and digits
/// (versions, sizes, English names) always look right. The Arabic font is only a
/// cascade fallback: it draws Arabic letters and nothing else.
public enum AppFont {
	/// PostScript names of the Arabic fallback font (IBM Plex Sans Arabic when shipped).
	nonisolated(unsafe) public private(set) static var regularName: String?
	nonisolated(unsafe) public private(set) static var heavyName: String?
	nonisolated(unsafe) private static var _registered = false

	/// Registers every font file shipped inside the app and remembers their names.
	public static func register() {
		guard !_registered else { return }
		_registered = true

		guard
			let root = Bundle.main.resourceURL,
			let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
		else {
			return
		}

		var names: [String] = []
		for case let url as URL in enumerator {
			let folder = url.lastPathComponent
			if folder == "Frameworks" || folder == "PlugIns" || folder == "_CodeSignature" {
				enumerator.skipDescendants()
				continue
			}

			let ext = url.pathExtension.lowercased()
			guard ext == "ttf" || ext == "otf" else { continue }

			CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
			if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
				for descriptor in descriptors {
					if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
						names.append(name)
					}
				}
			}
		}

		func isHeavy(_ name: String) -> Bool {
			let value = name.lowercased()
			return value.contains("black") || value.contains("heavy") || value.contains("bold")
		}

		// IBM Plex Sans Arabic is the Arabic font; any other shipped font is only a fallback
		let plex = names.filter { $0.hasPrefix("IBMPlexSansArabic") }
		let pool = plex.isEmpty ? names : plex
		heavyName = pool.first(where: { isHeavy($0) })
		regularName = pool.first(where: { !isHeavy($0) }) ?? pool.first
		if heavyName == nil { heavyName = regularName }
	}

	public static var isAvailable: Bool { regularName != nil }

	/// System font as the base, Arabic font as a cascade list (Arabic letters only).
	public static func mixedFont(arabic: String?, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
		let base = UIFont.systemFont(ofSize: size, weight: weight)
		guard let arabic else { return base }
		let descriptor = base.fontDescriptor.addingAttributes([
			.cascadeList: [UIFontDescriptor(fontAttributes: [.name: arabic])]
		])
		return UIFont(descriptor: descriptor, size: size)
	}

	private static func _make(_ size: CGFloat, heavy: Bool) -> Font {
		register()
		let arabic = heavy ? heavyName : regularName
		let uiFont = mixedFont(arabic: arabic, size: size, weight: heavy ? .bold : .regular)
		return Font(uiFont as CTFont)
	}

	public static var largeTitle: Font { _make(34, heavy: true) }
	public static var title: Font { _make(28, heavy: true) }
	public static var title2: Font { _make(22, heavy: true) }
	public static var title3: Font { _make(20, heavy: true) }
	public static var headline: Font { _make(17, heavy: true) }
	public static var body: Font { _make(17, heavy: false) }
	public static var callout: Font { _make(16, heavy: false) }
	public static var subheadline: Font { _make(15, heavy: false) }
	public static var footnote: Font { _make(13, heavy: false) }
	public static var caption: Font { _make(12, heavy: false) }
	public static var caption2: Font { _make(11, heavy: false) }

	/// Titles of navigation bars and the tab bar (UIKit parts of the interface).
	@MainActor
	public static func applyUIKitAppearance() {
		register()
		let titleFont = mixedFont(arabic: heavyName, size: 17, weight: .bold)
		let largeTitleFont = mixedFont(arabic: heavyName, size: 32, weight: .bold)
		let tabFont = mixedFont(arabic: regularName, size: 10, weight: .medium)

		UINavigationBar.appearance().titleTextAttributes = [.font: titleFont]
		UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitleFont]
		UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
		UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .selected)
	}
}

/// Version numbers inside Arabic text keep their left-to-right order.
public func isolatedLTR(_ text: String) -> String { "\u{2066}" + text + "\u{2069}" }

// MARK: - Colors
public enum AppTheme {
	/// Solid black in dark mode (the store is black everywhere).
	public static var background: Color {
		Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .black : .systemGroupedBackground })
	}

	/// Rows of settings-style lists: dark gray cards on the black background.
	public static var row: Color {
		Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.11, alpha: 1) : .secondarySystemGroupedBackground })
	}

	/// Buttons / pills / chips: the same dark gray as the cards.
	public static var pill: Color {
		Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : .tertiarySystemFill })
	}
}

// MARK: - Modifiers
public extension View {
	/// Every row is its own dark-gray rounded card (small gap between cards, no separators).
	func appRowBackground() -> some View {
		listRowBackground(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(AppTheme.row)
				.padding(.vertical, 3)
		)
		.listRowSeparator(.hidden)
	}

	/// Solid black behind a list / form.
	func appListBackground() -> some View {
		scrollContentBackground(.hidden)
			.background(AppTheme.background.ignoresSafeArea())
	}

	/// Liquid-glass top bar: no bar background, soft edge fade (iOS 26), glass buttons only.
	@ViewBuilder
	func appGlassTopBar() -> some View {
		if #available(iOS 26.0, *) {
			self
				.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
				.scrollEdgeEffectStyle(.soft, for: .top)
		} else {
			self.toolbarBackground(.hidden, for: .navigationBar)
		}
	}

	@ViewBuilder
	func appPresentationBackground() -> some View {
		if #available(iOS 16.4, *) {
			presentationBackground(AppTheme.background)
		} else {
			self
		}
	}
}
