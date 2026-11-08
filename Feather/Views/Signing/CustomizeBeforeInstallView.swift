//
//  CustomizeBeforeInstallView.swift
//  AppMaster
//
//  "Customize": the signing screen (name, identifier, version, icon, certificate,
//  tweaks, properties) opens right away, before anything is downloaded.
//  After "Install" the person can leave: the app is downloaded, signed with these
//  choices and the install prompt appears when it is ready (same as the Install button).
//

import SwiftUI
import PhotosUI
import NukeUI
import NimbleViews

struct CustomizeBeforeInstallView: View {
	@Environment(\.dismiss) var dismiss
	@StateObject private var _optionsManager = OptionsManager.shared

	let pending: PendingCustomize

	@State private var _options: Options = OptionsManager.shared.options
	@State private var _certificateIndex: Int
	@State private var _appIcon: UIImage?
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _selectedPhoto: PhotosPickerItem?

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	init(pending: PendingCustomize) {
		self.pending = pending
		let stored = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		__certificateIndex = State(initialValue: stored)
	}

	private func _selectedCertificate() -> CertificatePair? {
		guard _certificates.indices.contains(_certificateIndex) else { return nil }
		return _certificates[_certificateIndex]
	}

	// MARK: Body
	var body: some View {
		NBNavigationView("", displayMode: .inline) {
			Form {
				_customizationSection()
				_certificateSection()
				_advancedSection()

				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.overlay {
				VStack(spacing: 0) {
					Spacer()
					NBVariableBlurView()
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
						.rotationEffect(.degrees(180))
						.overlay {
							Button {
								_install()
							} label: {
								NBSheetButton(title: .localized("Install"), style: .prominent)
									.padding()
							}
							.buttonStyle(.plain)
							.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
						}
				}
				.ignoresSafeArea(edges: .bottom)
			}
			.toolbar {
				NBToolbarButton(role: .dismiss)
				NBToolbarButton(
					.localized("Reset"),
					style: .text,
					placement: .topBarTrailing
				) {
					_options = OptionsManager.shared.options
					_appIcon = nil
				}
			}
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.image],
					onDocumentsPicked: { urls in
						guard let url = urls.first else { return }
						_appIcon = UIImage.fromFile(url)?.resizeToSquare()
					}
				)
				.ignoresSafeArea()
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }
				Task {
					if
						let data = try? await newValue.loadTransferable(type: Data.self),
						let image = UIImage(data: data)?.resizeToSquare()
					{
						_appIcon = image
					}
				}
			}
		}
	}
}

// MARK: - Sections
extension CustomizeBeforeInstallView {
	@ViewBuilder
	private func _customizationSection() -> some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Choose from Files"), systemImage: "folder") { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos"), systemImage: "photo") { _isImagePickerPresenting = true }
			} label: {
				if let icon = _appIcon {
					Image(uiImage: icon)
						.appIconStyle()
				} else if let url = pending.iconURL {
					LazyImage(url: url) { state in
						if let image = state.image {
							image.appIconStyle()
						} else {
							Image("App_Unknown").appIconStyle()
						}
					}
				} else {
					Image("App_Unknown").appIconStyle()
				}
			}

			_infoCell(.localized("Name"), value: _options.appName ?? pending.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: _options.appName ?? pending.name,
					bindingValue: $_options.appName
				)
			}
			_infoCell(.localized("Identifier"), value: _options.appIdentifier ?? pending.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: _options.appIdentifier ?? (pending.identifier ?? ""),
					bindingValue: $_options.appIdentifier,
					certificateIdentifier: _selectedCertificate().flatMap { Storage.shared.getCertificateAppIdentifier(for: $0) }
				)
			}
			_infoCell(.localized("Version"), value: _options.appVersion ?? pending.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: _options.appVersion ?? (pending.version ?? ""),
					bindingValue: $_options.appVersion
				)
			}
		}
	}

	@ViewBuilder
	private func _certificateSection() -> some View {
		NBSection(.localized("Signing")) {
			if let cert = _selectedCertificate() {
				NavigationLink {
					CertificatesView(selectedCert: $_certificateIndex)
				} label: {
					CertificatesCellView(cert: cert)
				}
			} else {
				Text(.localized("No Certificate"))
					.font(AppFont.footnote)
					.foregroundColor(.disabled())
			}
		}
	}

	@ViewBuilder
	private func _advancedSection() -> some View {
		NBSection(.localized("Advanced")) {
			NavigationLink(.localized("Tweaks")) {
				SigningTweaksView(options: $_options)
			}

			NavigationLink(.localized("Properties")) {
				Form {
					SigningOptionsView(
						options: $_options,
						temporaryOptions: _optionsManager.options
					)
				}
				.navigationTitle(.localized("Properties"))
			}
		}
	}

	@ViewBuilder
	private func _infoCell<V: View>(_ title: String, value: String?, @ViewBuilder destination: () -> V) -> some View {
		NavigationLink {
			destination()
		} label: {
			LabeledContent(title) {
				Text(value ?? .localized("Unknown"))
			}
		}
	}
}

// MARK: - Install
extension CustomizeBeforeInstallView {
	private func _install() {
		let certificate = _selectedCertificate()

		guard certificate != nil || _options.signingOption != .default else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		UIImpactFeedbackGenerator(style: .light).impactOccurred()

		let customization = OneTapInstaller.Customization(
			options: _options,
			icon: _appIcon,
			certificate: certificate
		)
		let start = pending.start
		dismiss()
		// let the screen close first, then start download -> sign -> install
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
			start(customization)
		}
	}
}
