//
//  AppTheme.swift
//  AppMaster
//
//  App-wide look: the platform font ("The Year of Handicrafts", عام الحرف اليدوية)
//  and the solid black backgrounds.
//
//  The font files (.ttf / .otf) are picked up automatically from anywhere inside
//  the app bundle (put them in Feather/Resources/Fonts). Until they are added the
//  system font is used, so nothing breaks.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Font
public enum AppFont {
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

		heavyName = names.first(where: { isHeavy($0) })
		regularName = names.first(where: { !isHeavy($0) }) ?? names.first
		if heavyName == nil { heavyName = regularName }
	}

	public static var isAvailable: Bool { regularName != nil }

	private static func _make(_ style: Font.TextStyle, _ size: CGFloat, heavy: Bool) -> Font {
		register()
		if let name = heavy ? heavyName : regularName {
			return Font.custom(name, size: size, relativeTo: style)
		}
		return Font.system(style)
	}

	public static var largeTitle: Font { _make(.largeTitle, 34, heavy: true) }
	public static var title: Font { _make(.title, 28, heavy: true) }
	public static var title2: Font { _make(.title2, 22, heavy: true) }
	public static var title3: Font { _make(.title3, 20, heavy: true) }
	public static var headline: Font { _make(.headline, 17, heavy: true) }
	public static var body: Font { _make(.body, 17, heavy: false) }
	public static var callout: Font { _make(.callout, 16, heavy: false) }
	public static var subheadline: Font { _make(.subheadline, 15, heavy: false) }
	public static var footnote: Font { _make(.footnote, 13, heavy: false) }
	public static var caption: Font { _make(.caption, 12, heavy: false) }
	public static var caption2: Font { _make(.caption2, 11, heavy: false) }

	/// Navigation bars: fully transparent (no coloured strip) so the system draws the
	/// liquid-glass look; only the title font is customised. Also the tab bar font.
	@MainActor
	public static func applyUIKitAppearance() {
		let bar = UINavigationBarAppearance()
		bar.configureWithTransparentBackground()
		bar.shadowColor = .clear
		if let heavy = heavyName {
			if let titleFont = UIFont(name: heavy, size: 17) { bar.titleTextAttributes = [.font: titleFont] }
			if let largeFont = UIFont(name: heavy, size: 32) { bar.largeTitleTextAttributes = [.font: largeFont] }
		}
		UINavigationBar.appearance().standardAppearance = bar
		UINavigationBar.appearance().scrollEdgeAppearance = bar
		UINavigationBar.appearance().compactAppearance = bar
		UINavigationBar.appearance().compactScrollEdgeAppearance = bar

		if let regular = regularName, let tabFont = UIFont(name: regular, size: 10) {
			UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
			UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .selected)
		}
	}
}

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
