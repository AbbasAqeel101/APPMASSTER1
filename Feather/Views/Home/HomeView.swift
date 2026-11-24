//
//  HomeView.swift
//  AppMaster
//
//  App Store-style Home tab. Reads the company catalog source (added
//  automatically on first launch, see FeatherApp._addCompanySource) and
//  renders:
//   - a "Featured" section built from the source's `featuredApps` list
//   - one horizontally-scrolling row per distinct `app.category` value
//
//  Both `featuredApps` and `category` are already part of the AltStore
//  JSON format (see AltSourceKit/ASRepository.swift) and are populated by
//  whatever the dashboard's app-catalog-feed function outputs — so
//  "featuring" an app or naming a list is just setting those fields when
//  the app is added/edited on the dashboard, no extra iOS work needed.
//

import SwiftUI
import CoreData
import AltSourceKit
import NimbleViews
import NukeUI

// MARK: - Toolbar item without the system glass capsule
/// On iOS 26 every toolbar item is drawn inside a big round "glass" button, which
/// left our avatar/logo floating in the middle of an empty circle. This wrapper
/// removes that background (iOS 26+) so the image itself is the circle and fills
/// it edge to edge. On older iOS versions it is just a regular ToolbarItem.
struct AvatarToolbarItem<Content: View>: ToolbarContent {
	private let _placement: ToolbarItemPlacement
	private let _content: Content

	init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {
		self._placement = placement
		self._content = content()
	}

	var body: some ToolbarContent {
		if #available(iOS 26.0, *) {
			ToolbarItem(placement: _placement) { _content }
				.sharedBackgroundVisibility(.hidden)
		} else {
			ToolbarItem(placement: _placement) { _content }
		}
	}
}

/// Diameter of the round Home toolbar buttons (company logo + profile photo).
let kHomeToolbarAvatarSize: CGFloat = 38

// MARK: - Company icon button (Home toolbar, where the bell used to be)
struct CompanyIconButton: View {
	@State private var _isPresenting = false

	var body: some View {
		Button {
			_isPresenting = true
		} label: {
			Image("AppMasterGlyph")
				.renderingMode(.original)
				.appIconStyle(size: kHomeToolbarAvatarSize, isCircle: true)
		}
		.buttonStyle(.plain)
		.sheet(isPresented: $_isPresenting) {
			NBNavigationView(.localized("About")) {
				AboutView()
					.toolbar {
						ToolbarItem(placement: .topBarTrailing) {
							Button(.localized("Done")) { _isPresenting = false }
						}
					}
			}
		}
	}
}

// MARK: - View
struct HomeView: View {
	static let companySourceIdentifier = AppMasterConfig.companySourceIdentifier

	@StateObject private var viewModel = SourcesViewModel.shared
	@ObservedObject private var _layoutStore = HomeLayoutStore.shared
	@State private var _isProfilePresenting = false

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	private var _companySource: AltSource? {
		_sources.first(where: { $0.identifier == Self.companySourceIdentifier })
	}

	private var _companyRepo: ASRepository? {
		guard let source = _companySource else { return nil }
		return viewModel.sources[source]
	}

	// MARK: Body
	var body: some View {
		NBNavigationView("") {
			ScrollView {
				VStack(alignment: .leading, spacing: 28) {
					// the Home is empty until sections are added from the dashboard
					if let repo = _companyRepo {
						ForEach(_blocks) { block in
							_blockView(block, repo: repo)
						}
					}
				}
				.padding(.vertical, 12)
			}
			.toolbar {
				AvatarToolbarItem(placement: .topBarLeading) {
					Text(.localized("Today"))
						.font(.system(size: 30, weight: .bold))
						.foregroundStyle(.primary)
						.lineLimit(1)
						.fixedSize(horizontal: true, vertical: false)
				}
				AvatarToolbarItem(placement: .topBarTrailing) {
					Button {
						_isProfilePresenting = true
					} label: {
						ProfileToolbarIcon()
					}
					.buttonStyle(.plain)
				}
			}
			.sheet(isPresented: $_isProfilePresenting) {
				ProfileView()
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
		.task {
			await _layoutStore.refresh()
		}
		.refreshable {
			await _layoutStore.refresh()
			await viewModel.fetchSources(_sources, refresh: true)
		}
	}

	/// Sections come only from the dashboard; nothing is shown until they are added.
	private var _blocks: [HomeLayoutBlock] {
		_layoutStore.blocks ?? []
	}

	@ViewBuilder
	private func _blockView(_ block: HomeLayoutBlock, repo: ASRepository) -> some View {
		switch block.kind {
		case "slides":
			HomeSlidesSection(block: block, repo: repo, sourceURL: _companySource?.sourceURL)
		case "marquee":
			HomeMarqueeSection(block: block, repo: repo, sourceURL: _companySource?.sourceURL)
		case "featured":
			HomeFeaturedSection(block: block, repo: repo, sourceURL: _companySource?.sourceURL)
		case "apps":
			HomeAppsRowSection(block: block, repo: repo, sourceURL: _companySource?.sourceURL)
		case "lists":
			HomeListsSection(block: block, repo: repo, sourceURL: _companySource?.sourceURL)
		default:
			EmptyView()
		}
	}
}
