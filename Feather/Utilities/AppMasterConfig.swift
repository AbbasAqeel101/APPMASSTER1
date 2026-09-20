//
//  AppMasterConfig.swift
//  AppMaster
//
//  Single place for the company-specific constants used across the app,
//  so a link / version / identifier only ever has to be changed here.
//

import Foundation
import UIKit
import NimbleExtensions

enum AppMasterConfig {
	/// Identifier of the company catalog source (see FeatherApp._addCompanySource).
	static let companySourceIdentifier = "com.appmaster.companystore"

	/// Version shown in Profile > About AppMaster.
	static let displayVersion = "5.0"

	/// Telegram account of the developer. Used by "About AppMaster" and "Help & Support".
	static let developerURL = "https://t.me/auuua1"
	static let supportURL = "https://t.me/auuua1"

	/// Public endpoint (Supabase Edge Function) that returns the notifications
	/// you publish from the platform. Shown behind the bell button.
	static let notificationsURL = "https://seemtaruyoixqdfdqwfv.supabase.co/functions/v1/app-notifications"

	/// Base of the shareable referral link shown in Profile > Profile.
	/// TODO: point this at the real dashboard/website link once the referral
	/// system is wired to the platform (login + tracking).
	static let referralBaseURL = "https://t.me/auuua1"
}

// MARK: - Local profile (name is stored via @AppStorage, photo + referral code live here)
enum AppMasterProfile {
	private static let _referralKey = "AppMaster.referralCode"

	private static var _photoURL: URL {
		URL.applicationSupportDirectory.appendingPathComponent("AppMasterProfile.jpg")
	}

	static func loadPhoto() -> UIImage? {
		guard let data = try? Data(contentsOf: _photoURL) else { return nil }
		return UIImage(data: data)
	}

	static func savePhoto(_ image: UIImage) {
		let square: UIImage = image.resizeToSquare() ?? image
		let prepared: UIImage = square.resize(512, 512)
		guard let data = prepared.jpegData(compressionQuality: 0.85) else { return }
		try? FileManager.default.createDirectoryIfNeeded(at: _photoURL.deletingLastPathComponent())
		try? data.write(to: _photoURL, options: .atomic)
	}

	static func deletePhoto() {
		try? FileManager.default.removeFileIfNeeded(at: _photoURL)
	}

	/// Stable, locally generated code for this install.
	static var referralCode: String {
		if let existing = UserDefaults.standard.string(forKey: _referralKey), !existing.isEmpty {
			return existing
		}
		let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
		var code = ""
		for _ in 0..<8 {
			code.append(alphabet[Int.random(in: 0..<alphabet.count)])
		}
		UserDefaults.standard.set(code, forKey: _referralKey)
		return code
	}

	static var referralLink: String {
		"\(AppMasterConfig.referralBaseURL)?ref=\(referralCode)"
	}
}
