//
//  DownloadCounter.swift
//  AppMaster
//
//  Tells the platform that an app was installed, so the dashboard counter
//  (shown on the app page and used for "most downloaded") goes up.
//

import Foundation

enum DownloadCounter {
	private static let _endpoint = URL(string: "https://seemtaruyoixqdfdqwfv.supabase.co/functions/v1/app-download")!

	static func report(url: URL) {
		var request = URLRequest(url: _endpoint)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url.absoluteString])
		request.timeoutInterval = 15
		URLSession.shared.dataTask(with: request).resume()
	}
}
