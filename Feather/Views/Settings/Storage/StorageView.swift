//
//  StorageView.swift
//  AppMaster
//
//  Profile > Storage: shows how much space AppMaster uses on the device,
//  broken down by signed apps, imported apps, certificates, archives and
//  cache, lets the user delete individual apps, and clear the caches.
//

import SwiftUI
import CoreData
import Nuke
import NimbleViews
import NimbleExtensions

// MARK: - Size helpers
enum StorageUsage {
	/// Total on-disk size of a file or folder (recursive).
	static func size(of url: URL) -> Int64 {
		let fileManager = FileManager.default
		guard fileManager.fileExists(atPath: url.path) else { return 0 }

		let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
		var total: Int64 = 0

		guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else {
			return 0
		}

		for case let fileURL as URL in enumerator {
			guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
			if values.isRegularFile == true {
				total += Int64(values.totalFileAllocatedSize ?? 0)
			}
		}

		return total
	}

	static func networkCacheSize() -> Int64 {
		var total = Int64(URLCache.shared.currentDiskUsage)
		if let nukeCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
			total += Int64(nukeCache.totalSize)
		}
		return total
	}

	static func availableDeviceCapacity() -> Int64? {
		let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
		return values?.volumeAvailableCapacityForImportantUsage
	}

	static func format(_ bytes: Int64) -> String {
		ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
	}
}

// MARK: - Model
struct StorageBreakdown {
	var signed: Int64 = 0
	var imported: Int64 = 0
	var certificates: Int64 = 0
	var archives: Int64 = 0
	var other: Int64 = 0
	var cache: Int64 = 0
	var available: Int64?

	var total: Int64 {
		signed + imported + certificates + archives + other + cache
	}

	static func compute() -> StorageBreakdown {
		let fileManager = FileManager.default

		var result = StorageBreakdown()
		result.signed = StorageUsage.size(of: fileManager.signed)
		result.imported = StorageUsage.size(of: fileManager.unsigned)
		result.certificates = StorageUsage.size(of: fileManager.certificates)
		result.archives = StorageUsage.size(of: fileManager.archives)

		let documents = StorageUsage.size(of: URL.documentsDirectory)
		let known = result.signed + result.imported + result.certificates + result.archives
		result.other = max(0, documents - known)

		result.cache = StorageUsage.networkCacheSize() + StorageUsage.size(of: fileManager.temporaryDirectory)
		result.available = StorageUsage.availableDeviceCapacity()
		return result
	}
}

// MARK: - View
struct StorageView: View {
	@State private var _usage = StorageBreakdown()
	@State private var _isClearCachePresenting = false

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	// MARK: Body
	var body: some View {
		NBList(.localized("Storage")) {
			_summary()
			_categories()
			_cleanup()
		}
		.task {
			await _reload()
		}
		.alert(.localized("Free Up Space"), isPresented: $_isClearCachePresenting) {
			Button(.localized("Cancel"), role: .cancel) { }
			Button(.localized("Clear"), role: .destructive) {
				ResetView.clearWorkCache()
				ResetView.clearNetworkCache()
				Task { await _reload() }
			}
		} message: {
			Text(.localized("Temporary files and cached images will be removed. Your apps and certificates are not affected."))
		}
	}
}

// MARK: - Sections
extension StorageView {
	@ViewBuilder
	private func _summary() -> some View {
		Section {
			VStack(alignment: .leading, spacing: 12) {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Text(StorageUsage.format(_usage.total))
						.font(.largeTitle.bold())
					Text(verbatim: .localized("used by %@", arguments: Bundle.main.name))
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				_bar()

				if let available = _usage.available {
					Text(verbatim: .localized("%@ available on device", arguments: StorageUsage.format(available)))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.vertical, 6)
		}
	}

	@ViewBuilder
	private func _bar() -> some View {
		let segments: [(value: Int64, color: Color)] = [
			(_usage.signed, .blue),
			(_usage.imported, .indigo),
			(_usage.certificates, .green),
			(_usage.archives, .orange),
			(_usage.other, .gray),
			(_usage.cache, .pink)
		]
		let total = max(_usage.total, 1)

		GeometryReader { geometry in
			HStack(spacing: 2) {
				ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
					if segment.value > 0 {
						Capsule()
							.fill(segment.color)
							.frame(width: max(4, geometry.size.width * CGFloat(segment.value) / CGFloat(total)))
					}
				}
				Spacer(minLength: 0)
			}
		}
		.frame(height: 10)
		.background(Capsule().fill(Color(uiColor: .quaternarySystemFill)))
		.clipShape(Capsule())
	}

	@ViewBuilder
	private func _categories() -> some View {
		Section {
			NavigationLink {
				StorageAppsListView(kind: .signed)
			} label: {
				_row(
					title: .localized("Signed Apps"),
					count: _signedApps.count,
					size: _usage.signed,
					color: .blue,
					systemImage: "checkmark.seal.fill"
				)
			}

			NavigationLink {
				StorageAppsListView(kind: .imported)
			} label: {
				_row(
					title: .localized("Imported Apps"),
					count: _importedApps.count,
					size: _usage.imported,
					color: .indigo,
					systemImage: "square.and.arrow.down.fill"
				)
			}

			_row(
				title: .localized("Certificates"),
				count: _certificates.count,
				size: _usage.certificates,
				color: .green,
				systemImage: "doc.badge.gearshape.fill"
			)

			_row(
				title: .localized("Archives"),
				count: nil,
				size: _usage.archives,
				color: .orange,
				systemImage: "archivebox.fill"
			)

			_row(
				title: .localized("Other"),
				count: nil,
				size: _usage.other,
				color: .gray,
				systemImage: "ellipsis.circle.fill"
			)

			_row(
				title: .localized("Cache"),
				count: nil,
				size: _usage.cache,
				color: .pink,
				systemImage: "photo.stack.fill"
			)
		}
	}

	@ViewBuilder
	private func _cleanup() -> some View {
		Section {
			Button {
				_isClearCachePresenting = true
			} label: {
				HStack {
					Label(.localized("Free Up Space"), systemImage: "sparkles")
					Spacer()
					Text(StorageUsage.format(_usage.cache))
						.foregroundStyle(.secondary)
				}
			}
		} footer: {
			Text(.localized("Clears temporary files and cached images. Apps you downloaded or signed are kept."))
		}
	}

	@ViewBuilder
	private func _row(
		title: String,
		count: Int?,
		size: Int64,
		color: Color,
		systemImage: String
	) -> some View {
		HStack(spacing: 14) {
			Image(systemName: systemImage)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: 30, height: 30)
				.background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
				if let count {
					Text(verbatim: .localized("%lld items", arguments: count))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 0)

			Text(StorageUsage.format(size))
				.foregroundStyle(.secondary)
		}
	}
}

// MARK: - Actions
extension StorageView {
	private func _reload() async {
		let computed = await Task.detached(priority: .utility) {
			StorageBreakdown.compute()
		}.value
		_usage = computed
	}
}

// MARK: - Apps list (signed / imported) with delete
struct StorageAppsListView: View {
	enum Kind {
		case signed
		case imported
	}

	let kind: Kind

	@State private var _sizes: [String: Int64] = [:]

	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .snappy
	) private var _signedApps: FetchedResults<Signed>

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _importedApps: FetchedResults<Imported>

	private var _title: String {
		switch kind {
		case .signed: return .localized("Signed Apps")
		case .imported: return .localized("Imported Apps")
		}
	}

	private var _isEmpty: Bool {
		switch kind {
		case .signed: return _signedApps.isEmpty
		case .imported: return _importedApps.isEmpty
		}
	}

	// MARK: Body
	var body: some View {
		NBList(_title) {
			switch kind {
			case .signed:
				ForEach(_signedApps, id: \.uuid) { app in
					_row(app)
				}
				.onDelete { offsets in
					let doomed: [Signed] = offsets.map { _signedApps[$0] }
					for app in doomed {
						Storage.shared.deleteApp(for: app)
					}
				}
			case .imported:
				ForEach(_importedApps, id: \.uuid) { app in
					_row(app)
				}
				.onDelete { offsets in
					let doomed: [Imported] = offsets.map { _importedApps[$0] }
					for app in doomed {
						Storage.shared.deleteApp(for: app)
					}
				}
			}
		}
		.overlay {
			if _isEmpty {
				Text(.localized("No Apps"))
					.foregroundStyle(.secondary)
			}
		}
		.task {
			await _loadSizes()
		}
	}
}

// MARK: - Extension: view
extension StorageAppsListView {
	@ViewBuilder
	private func _row(_ app: AppInfoPresentable) -> some View {
		HStack(spacing: 12) {
			FRAppIconView(app: app, size: 46)

			VStack(alignment: .leading, spacing: 2) {
				Text(app.name ?? .localized("Unknown"))
					.font(.headline)
					.lineLimit(1)
				if let version = app.version {
					Text(version)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 0)

			if let uuid = app.uuid, let size = _sizes[uuid] {
				Text(StorageUsage.format(size))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
		}
	}

	private func _loadSizes() async {
		var items: [(uuid: String, url: URL)] = []

		switch kind {
		case .signed:
			for app in _signedApps {
				if let uuid = app.uuid, let url = Storage.shared.getUuidDirectory(for: app) {
					items.append((uuid: uuid, url: url))
				}
			}
		case .imported:
			for app in _importedApps {
				if let uuid = app.uuid, let url = Storage.shared.getUuidDirectory(for: app) {
					items.append((uuid: uuid, url: url))
				}
			}
		}

		let snapshot = items
		let result = await Task.detached(priority: .utility) { () -> [String: Int64] in
			var sizes: [String: Int64] = [:]
			for item in snapshot {
				sizes[item.uuid] = StorageUsage.size(of: item.url)
			}
			return sizes
		}.value

		_sizes = result
	}
}
