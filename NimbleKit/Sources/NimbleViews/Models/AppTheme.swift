//
//  AppTheme.swift
//  AppMaster
//
//  App-wide look: the system font and the solid black backgrounds.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Font
/// The system font only (SF Pro for Latin letters and digits, the system Arabic font for
/// Arabic) - exactly the look of the App Store. No custom font is shipped or registered.
public enum AppFont {
	/// Kept so existing calls compile; nothing to register any more.
	public static func register() {}

	public static var largeTitle: Font { Font.largeTitle.weight(.bold) }
	public static var title: Font { Font.title.weight(.bold) }
	public static var title2: Font { Font.title2.weight(.bold) }
	public static var title3: Font { Font.title3.weight(.bold) }
	public static var headline: Font { Font.headline }
	public static var body: Font { Font.body }
	public static var callout: Font { Font.callout }
	public static var subheadline: Font { Font.subheadline }
	public static var footnote: Font { Font.footnote }
	public static var caption: Font { Font.caption }
	public static var caption2: Font { Font.caption2 }

	/// Navigation / tab bars keep the system look.
	@MainActor
	public static func applyUIKitAppearance() {}
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
