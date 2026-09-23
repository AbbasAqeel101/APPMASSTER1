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

// MARK: - Company icon button (Home toolbar, where the bell used to be)
struct CompanyIconButton: View {
	@State private var _isPresenting = false

	var body: some View {
		Button {
			_isPresenting = true
		} label: {
			Image("AppMasterGlyph")
				.renderingMode(.original)
				.appIconStyle(size: 30, isCircle: true)
		}
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

	private var _featuredApps: [ASRepository.App] {
		guard let repo = _companyRepo else { return [] }
		let ids = repo.featuredApps ?? []
		if ids.isEmpty {
			// fall back to showing the newest few apps so Home is never empty
			return Array(repo.apps.prefix(5))
		}
		return repo.apps.filter { ids.contains($0.id ?? "") }
	}

	/// Apps grouped by their `category` field, in first-seen order.
	private var _categorizedLists: [(title: String, apps: [ASRepository.App])] {
		guard let repo = _companyRepo else { return [] }
		var order: [String] = []
		var groups: [String: [ASRepository.App]] = [:]

		for app in repo.apps {
			guard let category = app.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty else { continue }
			if groups[category] == nil {
				groups[category] = []
				order.append(category)
			}
			groups[category]?.append(app)
		}

		return order.map { (title: $0, apps: groups[$0] ?? []) }
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Home")) {
			ScrollView {
				VStack(alignment: .leading, spacing: 28) {
					if let repo = _companyRepo {
						if !_featuredApps.isEmpty {
							_featuredSection(repo: repo, apps: _featuredApps)
						}

						ForEach(_categorizedLists, id: \.title) { list in
							_appRow(repo: repo, title: list.title, apps: list.apps)
						}

						if _featuredApps.isEmpty && _categorizedLists.isEmpty {
							_emptyState()
						}
					} else {
						_loadingOrEmptyState()
					}
				}
				.padding(.vertical, 12)
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					CompanyIconButton()
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						_isProfilePresenting = true
					} label: {
						ProfileToolbarIcon()
					}
				}
			}
			.sheet(isPresented: $_isProfilePresenting) {
				ProfileView()
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
		.refreshable {
			await viewModel.fetchSources(_sources, refresh: true)
		}
	}
}

// MARK: - Sections
extension HomeView {
	@ViewBuilder
	private func _featuredSection(repo: ASRepository, apps: [ASRepository.App]) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(.localized("Featured"))
				.font(.title2.bold())
				.padding(.horizontal)

			TabView {
				ForEach(apps, id: \.currentUniqueId) { app in
					NavigationLink {
						SourceAppsDetailView(sourceURL: _companySource?.sourceURL, source: repo, app: app)
					} label: {
						_featuredCard(app: app)
					}
					.buttonStyle(.plain)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: apps.count > 1 ? .automatic : .never))
			.frame(height: 220)
		}
	}

	@ViewBuilder
	private func _featuredCard(app: ASRepository.App) -> some View {
		ZStack(alignment: .bottomLeading) {
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(app.tintColor ?? Color.accentColor)
				.opacity(0.85)

			HStack(spacing: 16) {
				if let iconURL = app.iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
							image.appIconStyle(size: 72)
						}
					}
				}
				VStack(alignment: .leading, spacing: 4) {
					Text(.localized("Featured App"))
						.font(.caption)
						.foregroundStyle(.white.opacity(0.85))
					Text(app.currentName)
						.font(.title3.bold())
						.foregroundStyle(.white)
					if let subtitle = app.currentDescription {
						Text(subtitle)
							.font(.subheadline)
							.foregroundStyle(.white.opacity(0.9))
							.lineLimit(2)
					}
				}
				Spacer()
			}
			.padding(20)
		}
		.padding(.horizontal)
	}

	@ViewBuilder
	private func _appRow(repo: ASRepository, title: String, apps: [ASRepository.App]) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.title3.bold())
				.padding(.horizontal)

			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 16) {
					ForEach(apps, id: \.currentUniqueId) { app in
						NavigationLink {
							SourceAppsDetailView(sourceURL: _companySource?.sourceURL, source: repo, app: app)
						} label: {
							_appTile(app: app)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal)
			}
		}
	}

	@ViewBuilder
	private func _appTile(app: ASRepository.App) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			if let iconURL = app.iconURL {
				LazyImage(url: iconURL) { state in
					if let image = state.image {
						image.appIconStyle(size: 90)
					} else {
						Image("App_Unknown").appIconStyle(size: 90)
					}
				}
			} else {
				Image("App_Unknown").appIconStyle(size: 90)
			}

			Text(app.currentName)
				.font(.footnote.weight(.medium))
				.lineLimit(1)
				.frame(width: 90, alignment: .leading)
		}
	}

	@ViewBuilder
	private func _loadingOrEmptyState() -> some View {
		VStack(spacing: 12) {
			ProgressView()
			Text(.localized("Loading apps…"))
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
		.padding(.top, 80)
	}

	@ViewBuilder
	private func _emptyState() -> some View {
		VStack(spacing: 8) {
			Image(systemName: "square.grid.2x2")
				.font(.system(size: 40))
				.foregroundStyle(.secondary)
			Text(.localized("No apps yet"))
				.font(.headline)
			Text(.localized("Apps you feature or categorize on the dashboard will show up here."))
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(.horizontal, 40)
		}
		.frame(maxWidth: .infinity)
		.padding(.top, 80)
	}
}
