//
//  CertificateFileHandler.swift
//  Feather
//
//  Created by samara on 15.04.2025.
//

import Foundation
import OSLog
import CryptoKit

final class CertificateFileHandler: NSObject {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	
	private let _key: URL
	private let _provision: URL
	private let _keyPassword: String?
	private let _certNickname: String?
	private let _isDefault: Bool
	
	private var _certPair: Certificate?
	
	init(
		key: URL,
		provision: URL,
		password: String? = nil,
		nickname: String? = nil,
		isDefault: Bool = false
	) {
		self._key = key
		self._provision = provision
		self._keyPassword = password
		self._certNickname = nickname
		self._isDefault = isDefault
		
		_certPair = CertificateReader(provision).decoded
		
		super.init()
	}
	
	func copy() async throws {
		guard
			(_certPair != nil)
		else {
			throw CertificateFileHandlerError.certNotValid
		}
		
		let destinationURL = try await _directory()

		try _fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
		try _fileManager.copyItem(at: _key, to: destinationURL.appendingPathComponent(_key.lastPathComponent))
		try _fileManager.copyItem(at: _provision, to: destinationURL.appendingPathComponent(_provision.lastPathComponent))
	}
	
	func addToDatabase() async throws {
		let uuid = _uuid
		let password = _keyPassword
		let nickname = _certNickname
		let ppq = _certPair?.PPQCheck ?? false
		let expiration = _certPair?.ExpirationDate ?? Date()
		let isDefault = _isDefault

		// Core Data's view context and the haptic generator must only be touched on the main thread
		await MainActor.run {
			Storage.shared.addCertificate(
				uuid: uuid,
				password: password,
				nickname: nickname,
				ppq: ppq,
				expiration: expiration,
				isDefault: isDefault
			) { _ in
				Logger.misc.info("[\(uuid)] Added to database")
			}
		}
	}
	
	private func _directory() async throws -> URL {
		// Documents/Feather/Certificates/\(UUID)
		_fileManager.certificates(_uuid)
	}
}

private enum CertificateFileHandlerError: Error {
	case certNotValid
}

// MARK: - Automatic certificate for subscribers
/// A subscriber's AppMaster is signed with the subscriber's own certificate, so
/// the provisioning profile embedded in the installed app identifies it. The
/// platform returns that certificate and the app imports it by itself.
enum AutoCertificateImporter {
	private static let _endpoint = "https://seemtaruyoixqdfdqwfv.supabase.co/functions/v1/device-cert"
	private static let _hashKey = "AppMaster.autoCertHash"

	static func run() async {
		guard
			let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
			let profileData = try? Data(contentsOf: profileURL),
			let endpoint = URL(string: _endpoint)
		else {
			return
		}

		let hash = SHA256.hash(data: profileData).map { String(format: "%02x", $0) }.joined()
		let hasCertificates = await MainActor.run { !Storage.shared.getAllCertificates().isEmpty }

		if hasCertificates && UserDefaults.standard.string(forKey: _hashKey) == hash {
			return
		}

		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.timeoutInterval = 25
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["profile_sha256": hash])

		guard
			let (data, response) = try? await URLSession.shared.data(for: request),
			(response as? HTTPURLResponse)?.statusCode == 200,
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let p12Base64 = json["p12"] as? String,
			let provisionBase64 = json["mobileprovision"] as? String,
			let password = json["password"] as? String,
			let p12URL = FileManager.default.decodeAndWrite(base64: p12Base64, pathComponent: ".p12"),
			let provisionURL = FileManager.default.decodeAndWrite(base64: provisionBase64, pathComponent: ".mobileprovision")
		else {
			return
		}

		let valid = FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL)
		guard valid else { return }

		let nickname = (json["name"] as? String) ?? ""
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			FR.handleCertificateFiles(
				p12URL: p12URL,
				provisionURL: provisionURL,
				p12Password: password,
				certificateName: nickname,
				isDefault: true
			) { error in
				if error == nil {
					UserDefaults.standard.set(hash, forKey: _hashKey)
				}
				continuation.resume()
			}
		}
	}
}
