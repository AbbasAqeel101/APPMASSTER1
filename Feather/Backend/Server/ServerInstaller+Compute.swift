//
//  Server+Compute.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import UIKit.UIGraphicsImageRenderer

extension ServerInstaller {
	var plistEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/\(id).plist"
		comps.port = port
		return comps.url!
	}

	var payloadEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/\(id).ipa"
		comps.port = port
		return comps.url!
	}
	
	var pageEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = self.getServerMethod() == 1 ? "http" : "https"
		comps.host = sni()
		comps.path = "/install"
		comps.port = port
		return comps.url!
	}
	
	var externalServerLink: String {
		let baseUrl = "https://api.palera.in/genPlist?bundleid=\(app.identifier!)&name=\(app.name!)&version=\(app.version!)&fetchurl=\(self.payloadEndpoint.absoluteString)"
		let encodedBaseUrl = baseUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
		let finalEncodedUrl = encodedBaseUrl.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
		
		return finalEncodedUrl
	}

	var iTunesLink: String {
		_iTunesLink(with: plistEndpoint.absoluteString)
	}
	
	var iTunesLinkExternal: String {
		_iTunesLink(with: externalServerLink)
	}
	
	private func _iTunesLink(with url: String) -> String {
		return "itms-services://?action=download-manifest&url=\(url)"
	}

	var displayImageSmallEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = sni()
		comps.path = "/app57x57.png"
		comps.port = port
		return comps.url!
	}

	var displayImageLargeEndpoint: URL {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = sni()
		comps.path = "/app512x512.png"
		comps.port = port
		return comps.url!
	}
	
	var displayImageSmallData: Data {
		_createIcon(57)
	}
	
	var displayImageLargeData: Data {
		_createIcon(512)
	}
	
	private func _createIcon(_ r: CGFloat) -> Data {
		let renderer = UIGraphicsImageRenderer(size: .init(width: r, height: r))
		let logo = UIImage(named: "AppMasterLogo")
		let image = renderer.image { ctx in
			UIColor.black.setFill()
			ctx.fill(.init(x: 0, y: 0, width: r, height: r))
			logo?.draw(in: .init(x: 0, y: 0, width: r, height: r))
		}
		return image.pngData()!
	}

	var html: String {
		"""
		<html style="background-color: black;">
		<script type="text/javascript">window.location="\(iTunesLinkExternal)"</script>
		</html>
		"""
	}

	var installManifest: [String: Any] {[
		"items": [[
			"assets": [
				[
					"kind": "software-package",
					"url": payloadEndpoint.absoluteString,
				],
				[
					"kind": "display-image",
					"url": displayImageSmallEndpoint.absoluteString,
				],
				[
					"kind": "full-size-image",
					"url": displayImageLargeEndpoint.absoluteString,
				],
			],
			"metadata": [
				"bundle-identifier": app.identifier,
				"bundle-version": app.version,
				"kind": "software",
				"title": app.name,
			],
		],],
	]}

	var installManifestData: Data {
		(try? PropertyListSerialization.data(
			fromPropertyList: installManifest,
			format: .xml,
			options: .zero
		)) ?? .init()
	}
}

// MARK: - Automatic SSL certificate refresh
/// The local install server needs a valid HTTPS certificate. The certificate is renewed
/// automatically on the server side (GitHub Actions) and published as pack.json; the app
/// downloads it in the background, at most once a day.
enum ServerCertUpdater {
	static let packURL = "https://cert.appmaster.app/pack.json"
	private static let _lastKey = "AppMaster.sslPackLastUpdate"

	static func markUpdated() {
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: _lastKey)
	}

	/// Call on launch / when the app returns to the foreground.
	static func refreshIfNeeded(force: Bool = false) {
		let last = UserDefaults.standard.double(forKey: _lastKey)
		guard force || Date().timeIntervalSince1970 - last > 24 * 3600 else { return }

		FR.downloadSSLCertificates(from: packURL) { success in
			if success { ServerCertUpdater.markUpdated() }
		}
	}
}
