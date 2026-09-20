//
//  BackupRestoreView.swift
//  AppMaster
//
//  Profile > Backup & Restore: exports the app's settings and sources — and,
//  optionally, the downloaded (signed / imported) apps themselves — into a
//  single .zip that is shared through the iOS share sheet, and restores from
//  such a file. Certificates are intentionally NOT included.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
import Zip
import NimbleViews
import NimbleExtensions

// MARK: - Errors
private enum BackupError: LocalizedError {
	case invalidFile

	var errorDescription: String? {
		String.localized("This file is not a valid AppMaster backup.")
	}
}

// MARK: - View
struct BackupRestoreView: View {
	@State private var _includeApps = false
	@State private var _isWorking = false
	@State private var _workingText = ""
	@State private var _isImporterPresenting = false
	@State private var _isAlertPresenting = false
	@State private var _alertTitle = ""
	@State private var _alertMessage = ""

	private static let _keyPrefixes: [String] = ["Feather.", "feather.", "AppMaster."]

	// MARK: Body
	var body: some View {
		NBList(.localized("Backup & Restore")) {
			Section {
				Toggle(isOn: $_includeApps) {
					Label(.localized("Include downloaded apps"), systemImage: "square.stack.3d.up")
				}
				.disabled(_isWorking)
			} footer: {
				Text(.localized("Adds your signed and imported apps to the backup. The file can be several GB, so keep enough free space."))
			}

			Section {
				Button {
					_createBackup()
				} label: {
					Label(.localized("Create Backup"), systemImage: "square.and.arrow.up")
				}
				.disabled(_isWorking)

				Button {
					_isImporterPresenting = true
				} label: {
					Label(.localized("Restore from Backup"), systemImage: "square.and.arrow.down")
				}
				.disabled(_isWorking)

				if _isWorking {
					HStack(spacing: 10) {
						ProgressView()
						Text(_workingText)
							.foregroundStyle(.secondary)
					}
				}
			} footer: {
				Text(.localized("A backup always contains your app settings and sources. Certificates are never included."))
			}
		}
		.fileImporter(
			isPresented: $_isImporterPresenting,
			allowedContentTypes: [.zip]
		) { result in
			_handleImport(result)
		}
		.alert(_alertTitle, isPresented: $_isAlertPresenting) {
			Button(.localized("OK"), role: .cancel) { }
		} message: {
			Text(_alertMessage)
		}
	}
}

// MARK: - Backup
extension BackupRestoreView {
	private static func _isBackedUp(_ key: String) -> Bool {
		for prefix in _keyPrefixes {
			if key.hasPrefix(prefix) { return true }
		}
		return false
	}

	private static func _record(for app: AppInfoPresentable) -> [String: String]? {
		guard let uuid = app.uuid else { return nil }

		var entry: [String: String] = ["uuid": uuid]
		if let name = app.name { entry["name"] = name }
		if let identifier = app.identifier { entry["identifier"] = identifier }
		if let version = app.version { entry["version"] = version }
		if let icon = app.icon { entry["icon"] = icon }
		if let source = app.source { entry["source"] = source.absoluteString }
		return entry
	}

	/// Runs on the main thread (reads Core Data).
	private func _makeManifestData(includeApps: Bool) -> Data? {
		var settings: [String: Any] = [:]
		for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
			guard Self._isBackedUp(key) else { continue }
			if value is String || value is NSNumber {
				settings[key] = value
			}
		}

		var sources: [[String: String]] = []
		for source in Storage.shared.getSources() {
			guard
				let url = source.sourceURL,
				let identifier = source.identifier
			else {
				continue
			}

			var entry: [String: String] = [
				"url": url.absoluteString,
				"identifier": identifier
			]
			if let name = source.name {
				entry["name"] = name
			}
			if let icon = source.iconURL {
				entry["icon"] = icon.absoluteString
			}
			sources.append(entry)
		}

		var signed: [[String: String]] = []
		var imported: [[String: String]] = []

		if includeApps {
			let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
			for app in (try? Storage.shared.context.fetch(signedRequest)) ?? [] {
				if let record = Self._record(for: app) { signed.append(record) }
			}

			let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
			for app in (try? Storage.shared.context.fetch(importedRequest)) ?? [] {
				if let record = Self._record(for: app) { imported.append(record) }
			}
		}

		let root: [String: Any] = [
			"app": "AppMaster",
			"version": 2,
			"createdAt": ISO8601DateFormatter().string(from: Date()),
			"includesApps": includeApps,
			"settings": settings,
			"sources": sources,
			"signed": signed,
			"imported": imported
		]

		return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
	}

	/// Runs off the main thread.
	private static func _writeArchive(manifestData: Data, includeApps: Bool) throws -> URL {
		let fileManager = FileManager.default

		let workDir = fileManager.temporaryDirectory
			.appendingPathComponent("AppMasterBackup_\(UUID().uuidString)", isDirectory: true)
		try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

		let manifestURL = workDir.appendingPathComponent("manifest.json")
		try manifestData.write(to: manifestURL, options: .atomic)

		var paths: [URL] = [manifestURL]
		if includeApps {
			if fileManager.fileExists(atPath: fileManager.signed.path) {
				paths.append(fileManager.signed)
			}
			if fileManager.fileExists(atPath: fileManager.unsigned.path) {
				paths.append(fileManager.unsigned)
			}
		}

		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd"

		let zipURL = fileManager.temporaryDirectory
			.appendingPathComponent("AppMaster-Backup-\(formatter.string(from: Date())).zip")
		try? fileManager.removeItem(at: zipURL)

		try Zip.zipFiles(
			paths: paths,
			zipFilePath: zipURL,
			password: nil,
			compression: .BestSpeed,
			progress: nil
		)

		try? fileManager.removeItem(at: workDir)
		return zipURL
	}

	private func _createBackup() {
		let includeApps = _includeApps

		guard let manifestData = _makeManifestData(includeApps: includeApps) else {
			_show(title: .localized("Error"), message: .localized("Could not create the backup."))
			return
		}

		_workingText = .localized("Creating backup…")
		_isWorking = true

		Task {
			do {
				let zipURL = try await Task.detached(priority: .utility) {
					try BackupRestoreView._writeArchive(manifestData: manifestData, includeApps: includeApps)
				}.value

				_isWorking = false
				UIActivityViewController.show(activityItems: [zipURL])
			} catch {
				_isWorking = false
				_show(title: .localized("Error"), message: error.localizedDescription)
			}
		}
	}
}

// MARK: - Restore
extension BackupRestoreView {
	private static func _extract(_ url: URL) throws -> URL {
		let isAccessing = url.startAccessingSecurityScopedResource()
		defer {
			if isAccessing { url.stopAccessingSecurityScopedResource() }
		}

		let fileManager = FileManager.default
		let workDir = fileManager.temporaryDirectory
			.appendingPathComponent("AppMasterRestore_\(UUID().uuidString)", isDirectory: true)
		try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)

		try Zip.unzipFile(
			url,
			destination: workDir,
			overwrite: true,
			password: nil,
			progress: nil
		)

		return workDir
	}

	private func _handleImport(_ result: Result<URL, Error>) {
		switch result {
		case .success(let url):
			_workingText = .localized("Restoring…")
			_isWorking = true

			Task {
				do {
					let workDir = try await Task.detached(priority: .utility) {
						try BackupRestoreView._extract(url)
					}.value

					let restoredApps = try _apply(workDir: workDir)
					try? FileManager.default.removeItem(at: workDir)

					_isWorking = false

					var message: String = .localized("Backup restored. Restart the app so every setting applies.")
					if restoredApps > 0 {
						message += "\n" + String.localized("Apps restored: %lld", arguments: restoredApps)
					}
					_show(title: .localized("Success"), message: message)
				} catch {
					_isWorking = false
					_show(title: .localized("Error"), message: error.localizedDescription)
				}
			}
		case .failure(let error):
			_show(title: .localized("Error"), message: error.localizedDescription)
		}
	}

	/// Applies the extracted backup. Returns how many apps were restored.
	private func _apply(workDir: URL) throws -> Int {
		let manifestURL = workDir.appendingPathComponent("manifest.json")
		let data = try Data(contentsOf: manifestURL)

		guard
			let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			(root["app"] as? String) == "AppMaster"
		else {
			throw BackupError.invalidFile
		}

		if let settings = root["settings"] as? [String: Any] {
			for (key, value) in settings {
				guard Self._isBackedUp(key) else { continue }
				UserDefaults.standard.set(value, forKey: key)
			}
		}

		if let sources = root["sources"] as? [[String: Any]] {
			for entry in sources {
				guard
					let urlString = entry["url"] as? String,
					let sourceURL = URL(string: urlString),
					let identifier = entry["identifier"] as? String
				else {
					continue
				}

				let name = entry["name"] as? String
				var iconURL: URL?
				if let iconString = entry["icon"] as? String {
					iconURL = URL(string: iconString)
				}

				Storage.shared.addSource(
					sourceURL,
					name: name,
					identifier: identifier,
					iconURL: iconURL
				) { _ in }
			}
		}

		var restored = 0
		if let signed = root["signed"] as? [[String: String]] {
			restored += _restoreApps(signed, isSigned: true, workDir: workDir)
		}
		if let imported = root["imported"] as? [[String: String]] {
			restored += _restoreApps(imported, isSigned: false, workDir: workDir)
		}
		return restored
	}

	private func _restoreApps(_ records: [[String: String]], isSigned: Bool, workDir: URL) -> Int {
		let fileManager = FileManager.default

		let sourceRoot = workDir.appendingPathComponent(isSigned ? "Signed" : "Unsigned", isDirectory: true)
		let destinationRoot = isSigned ? fileManager.signed : fileManager.unsigned
		try? fileManager.createDirectoryIfNeeded(at: destinationRoot)

		var restored = 0

		for record in records {
			guard let uuid = record["uuid"] else { continue }

			let from = sourceRoot.appendingPathComponent(uuid, isDirectory: true)
			let to = destinationRoot.appendingPathComponent(uuid, isDirectory: true)

			guard
				fileManager.fileExists(atPath: from.path),
				!fileManager.fileExists(atPath: to.path)
			else {
				continue
			}

			do {
				try fileManager.moveItem(at: from, to: to)
			} catch {
				continue
			}

			var sourceURL: URL?
			if let sourceString = record["source"] {
				sourceURL = URL(string: sourceString)
			}

			if isSigned {
				Storage.shared.addSigned(
					uuid: uuid,
					source: sourceURL,
					certificate: nil,
					appName: record["name"],
					appIdentifier: record["identifier"],
					appVersion: record["version"],
					appIcon: record["icon"]
				) { _ in }
			} else {
				Storage.shared.addImported(
					uuid: uuid,
					source: sourceURL,
					appName: record["name"],
					appIdentifier: record["identifier"],
					appVersion: record["version"],
					appIcon: record["icon"]
				) { _ in }
			}

			restored += 1
		}

		return restored
	}

	private func _show(title: String, message: String) {
		_alertTitle = title
		_alertMessage = message
		_isAlertPresenting = true
	}
}
