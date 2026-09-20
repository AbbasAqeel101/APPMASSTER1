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
	case apps
	case games
	case library
	case sources
	case settings
	case certificates
	
	var title: String {
		switch self {
		case .home:				return .localized("Home")
		case .sources:     	return .localized("Sources")
		case .apps:			return .localized("Apps")
		case .games:		return .localized("Games")
		case .library: 		return .localized("Library")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		}
	}
	
	var icon: String {
		switch self {
		case .home:			return "house.fill"
		case .sources: 		return "globe.desk"
		case .apps:			return "square.stack.3d.up.fill"
		case .games:		return TabEnum._gamesIcon
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
		case .apps: CatalogAppsView(kind: .apps)
		case .games: CatalogAppsView(kind: .games)
		case .library: LibraryView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}
	
	/// The App Store's rocket for Games (falls back to a game controller on
	/// systems that don't ship that symbol).
	static var _gamesIcon: String {
		UIImage(systemName: "rocket.fill") != nil ? "rocket.fill" : "gamecontroller.fill"
	}
	
	/// Tabs shown in the bottom bar: Home, Apps, Games and Sources (plus the
	/// separate search button on iOS 26). The Library of downloaded apps is opened
	/// from the download button in the Apps tab, and Settings/Certificates are
	/// reached through the Profile screen (profile icon in Home).
	static var defaultTabs: [TabEnum] {
		return [
			.home,
			.apps,
			.games,
			.sources
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
