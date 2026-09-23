//
//  OneTapInstaller.swift
//  AppMaster
//
//  "One tap" install for the company apps:
//
//      Get  ->  download the IPA  ->  sign it with the default certificate
//           ->  hand it to the normal installer (itms-services prompt)
//
//  Everything runs on the device with the certificate that is already stored in
//  the app (Zsign is built in), so there is no server involved. The status is
//  shown as a small capsule at the bottom of the screen ("Signing ...", "Ready ...")
//  like in other stores.
//

import SwiftUI
import CoreData
import UIKit

final class OneTapInstaller: ObservableObject {
	static let shared = OneTapInstaller()

	enum Phase: Equatable {
		case idle
		case downloading(String)
		case signing(String)
		case ready(String)
		case failed(String)
	}

	@Published private(set) var phase: Phase = .idle
	/// Presented as the install sheet by the root view once signing is done.
	@Published var installApp: AnyApp?

	private var _hideItem: DispatchWorkItem?

	// MARK: Public

	/// Call right before starting the download. Returns `false` (and explains why in the
	/// toast) when the app can't be signed automatically; the download then behaves like
	/// before and the app is just saved in the Library.
	@discardableResult
	func begin(name: String) -> Bool {
		guard _canSign else {
			_set(.failed(.localized("Add a certificate first. The app will be saved in the Library.")), hideAfter: 5)
			return false
		}
		_set(.downloading(name))
		return true
	}

	func reset() {
		_set(.idle)
	}

	func fail(_ message: String) {
		_stopBackgroundKeepAlive()
		_set(.failed(message), hideAfter: 6)
	}

	/// Called by `DownloadManager` when the IPA has been unpacked into the Library.
	func importFinished(download: Download, error: Error?) {
		if let error {
			fail(error.localizedDescription)
			return
		}

		guard
			let uuid = download.importedUUID,
			let app = _importedApp(uuid: uuid)
		else {
			fail(.localized("Could not find the downloaded app."))
			return
		}

		_sign(app)
	}

	// MARK: Signing

	private var _canSign: Bool {
		_defaultCertificate() != nil || OptionsManager.shared.options.signingOption != .default
	}

	private func _defaultCertificate() -> CertificatePair? {
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		return Storage.shared.getCertificate(for: index) ?? Storage.shared.getAllCertificates().first
	}

	private func _sign(_ app: Imported) {
		let name = app.name ?? ""
		let certificate = _defaultCertificate()

		guard certificate != nil || OptionsManager.shared.options.signingOption != .default else {
			fail(.localized("Please go to settings and import a valid certificate"))
			return
		}

		_set(.signing(name))
		_startBackgroundKeepAlive()

		// Same rules the manual signing screen applies before "Start Signing"
		var options = OptionsManager.shared.options

		if
			options.ppqProtection,
			let identifier = app.identifier,
			let certificate,
			certificate.ppQCheck
		{
			options.appIdentifier = "\(identifier).\(options.ppqString)"
		}

		if
			let current = app.identifier,
			let custom = options.identifiers[current]
		{
			options.appIdentifier = custom
		}

		if
			let current = app.name,
			let custom = options.displayNames[current]
		{
			options.appName = custom
		}

		// A profile with an explicit App ID only installs an app that uses exactly that
		// identifier, so use the certificate's identifier automatically.
		if
			let certificate,
			let certificateIdentifier = Storage.shared.getCertificateAppIdentifier(for: certificate)
		{
			options.appIdentifier = certificateIdentifier
		}

		let finalOptions = options

		FR.signPackageFile(
			app,
			using: finalOptions,
			icon: nil,
			certificate: certificate
		) { [weak self] error in
			guard let self else { return }

			if let error {
				self.fail(error.localizedDescription)
				return
			}

			if finalOptions.post_deleteAppAfterSigned {
				Storage.shared.deleteApp(for: app)
			}

			guard let signed = self._latestSigned() else {
				self.fail(.localized("Could not find the downloaded app."))
				return
			}

			self._stopBackgroundKeepAlive()
			self._set(.ready(signed.name ?? name), hideAfter: 5)
			// the install sheet starts the local server and opens the iOS install prompt
			self.installApp = AnyApp(base: signed)
		}
	}

	// MARK: Storage helpers

	private func _importedApp(uuid: String) -> Imported? {
		let request: NSFetchRequest<Imported> = Imported.fetchRequest()
		request.predicate = NSPredicate(format: "uuid == %@", uuid)
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	private func _latestSigned() -> Signed? {
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
		request.fetchLimit = 1
		return try? Storage.shared.context.fetch(request).first
	}

	// MARK: State

	private func _set(_ new: Phase, hideAfter: TimeInterval? = nil) {
		let apply = { [weak self] in
			guard let self else { return }
			self._hideItem?.cancel()
			self._hideItem = nil
			self.phase = new

			if let hideAfter {
				let item = DispatchWorkItem { [weak self] in
					self?.phase = .idle
				}
				self._hideItem = item
				DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: item)
			}
		}

		if Thread.isMainThread {
			apply()
		} else {
			DispatchQueue.main.async(execute: apply)
		}
	}

	// Keeps the app alive for the few seconds signing needs if the person leaves the app.
	private func _startBackgroundKeepAlive() {
		#if !targetEnvironment(macCatalyst)
		DispatchQueue.main.async { BackgroundAudioManager.shared.start() }
		#endif
	}

	private func _stopBackgroundKeepAlive() {
		#if !targetEnvironment(macCatalyst)
		DispatchQueue.main.async {
			// other downloads may still need the keep-alive
			if DownloadManager.shared.downloads.isEmpty {
				BackgroundAudioManager.shared.stop()
			}
		}
		#endif
	}
}

// MARK: - Toast (bottom capsule)
struct OneTapToastView: View {
	@ObservedObject private var _installer = OneTapInstaller.shared

	private var _content: (text: String, icon: String?, isBusy: Bool)? {
		switch _installer.phase {
		case .idle:
			return nil
		case .downloading(let name):
			return (String.localized("Downloading %@", arguments: name), nil, true)
		case .signing(let name):
			return (String.localized("Signing %@", arguments: name), nil, true)
		case .ready(let name):
			return (String.localized("Ready to install %@", arguments: name), "checkmark.seal.fill", false)
		case .failed(let message):
			return (message, "exclamationmark.triangle.fill", false)
		}
	}

	var body: some View {
		ZStack {
			if let content = _content {
				HStack(spacing: 12) {
					Text(content.text)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
						.truncationMode(.tail)

					Spacer(minLength: 8)

					if content.isBusy {
						ProgressView()
					} else if let icon = content.icon {
						Image(systemName: icon)
							.font(.body)
					}
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 14)
				.background(.regularMaterial, in: Capsule())
				.overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
				.shadow(color: .black.opacity(0.18), radius: 10, y: 4)
				.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.smooth, value: _installer.phase)
		.allowsHitTesting(false)
	}
}
