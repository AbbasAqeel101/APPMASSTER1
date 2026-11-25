//
//  VPNGuard.swift
//  AppMaster
//
//  Blocks the whole store while a VPN / proxy is active (these are what link
//  sniffers use). A full-screen window above everything (sheets included) shows
//  the warning and disappears when the VPN / proxy is turned off.
//

import SwiftUI
import UIKit
import CFNetwork

@MainActor
final class VPNGuard {
	static let shared = VPNGuard()

	private var _window: UIWindow?
	private var _timer: Timer?

	private init() {}

	func start() {
		guard _timer == nil else { return }
		_check()
		_timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
			Task { @MainActor in self?._check() }
		}
		NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			Task { @MainActor in self?._check() }
		}
	}

	private func _check() {
		if Self.isActive() {
			_show()
		} else {
			_hide()
		}
	}

	private func _show() {
		guard _window == nil else { return }
		guard let scene = UIApplication.shared.connectedScenes
			.compactMap({ $0 as? UIWindowScene })
			.first else { return }

		let window = UIWindow(windowScene: scene)
		window.windowLevel = .alert + 1
		window.rootViewController = UIHostingController(rootView: VPNBlockView())
		window.makeKeyAndVisible()
		_window = window
	}

	private func _hide() {
		guard let window = _window else { return }
		window.isHidden = true
		_window = nil
	}

	/// True while a VPN tunnel or a proxy is in use.
	nonisolated static func isActive() -> Bool {
		// 1) tunnel interfaces that carry an IPv4 address (system utun interfaces have none)
		var list: UnsafeMutablePointer<ifaddrs>?
		if getifaddrs(&list) == 0 {
			defer { freeifaddrs(list) }
			var pointer = list
			while let item = pointer {
				let name = String(cString: item.pointee.ifa_name)
				let isTunnel = ["utun", "ppp", "ipsec", "tap", "tun"].contains { name.hasPrefix($0) }
				if isTunnel,
				   item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
				   let address = item.pointee.ifa_addr,
				   address.pointee.sa_family == UInt8(AF_INET) {
					return true
				}
				pointer = item.pointee.ifa_next
			}
		}

		guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
			return false
		}

		// 2) VPN interfaces listed by the system network settings
		if let scoped = settings["__SCOPED__"] as? [String: Any] {
			for key in scoped.keys {
				let value = key.lowercased()
				if value.contains("tap") || value.contains("tun") || value.contains("ppp") || value.contains("ipsec") {
					return true
				}
			}
		}

		// 3) a proxy (manual or automatic)
		for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable"] {
			if (settings[key] as? NSNumber)?.boolValue == true { return true }
		}
		return false
	}
}

struct VPNBlockView: View {
	private var _isArabic: Bool {
		(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ar")
	}

	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()
			Text(verbatim: _isArabic
				 ? "لقد رصدنا نشاط مشبوه ان تكرار هذه العملية قد يؤدي الى ايقاف إشتراكك"
				 : "We detected suspicious activity. Repeating this may lead to suspending your subscription.")
				.font(AppFont.title3)
				.foregroundStyle(.white)
				.multilineTextAlignment(.center)
				.padding(32)
		}
		.environment(\.layoutDirection, _isArabic ? .rightToLeft : .leftToRight)
		.preferredColorScheme(.dark)
	}
}
