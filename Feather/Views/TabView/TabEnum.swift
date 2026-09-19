//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case home
	case library
	case sources
	case settings
	case certificates
	
	var title: String {
		switch self {
		case .home:				return .localized("Home")
		case .sources:     	return .localized("Sources")
		case .library: 		return .localized("Apps")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		}
	}
	
	var icon: String {
		switch self {
		case .home:			return "house.fill"
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .home: HomeView()
		case .sources: SourcesView()
		case .library: LibraryView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}
	
	/// Tabs shown in the bottom bar. AppMaster only exposes Home, Apps and Sources here —
	/// Settings/Certificates are still fully functional but are reached through the
	/// Profile screen (tap the avatar in Home) instead of taking up a tab slot.
	static var defaultTabs: [TabEnum] {
		return [
			.home,
			.library,
			.sources
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
