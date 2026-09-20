//
//  EditProfileView.swift
//  AppMaster
//
//  Profile > Profile: change the photo, the display name, and share the
//  personal referral link. Stored locally for now; once the Profile screen
//  is wired to the company backend this should read/write the account
//  record tied to the device instead.
//

import SwiftUI
import PhotosUI
import NimbleViews

struct EditProfileView: View {
	@AppStorage("AppMaster.profileName") private var _profileName: String = ""
	@AppStorage("AppMaster.profilePhotoVersion") private var _photoVersion: Int = 0

	@State private var _pickerItem: PhotosPickerItem?
	@State private var _didCopyLink = false

	private var _hasPhoto: Bool {
		AppMasterProfile.loadPhoto() != nil
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Profile")) {
			_photoSection()

			Section(.localized("Name")) {
				TextField(.localized("Name"), text: $_profileName)
			}

			_referralSection()
		}
		.onChange(of: _pickerItem) { newItem in
			guard let newItem else { return }
			Task {
				if
					let data = try? await newItem.loadTransferable(type: Data.self),
					let image = UIImage(data: data)
				{
					AppMasterProfile.savePhoto(image)
					_photoVersion += 1
				}
				_pickerItem = nil
			}
		}
	}
}

// MARK: - Sections
extension EditProfileView {
	@ViewBuilder
	private func _photoSection() -> some View {
		Section {
			VStack(spacing: 12) {
				ProfileAvatarView(size: 104)

				PhotosPicker(selection: $_pickerItem, matching: .images) {
					Text(.localized("Change Photo"))
				}

				if _hasPhoto {
					Button(.localized("Remove Photo"), role: .destructive) {
						AppMasterProfile.deletePhoto()
						_photoVersion += 1
					}
					.font(.footnote)
				}
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
		}
		.listRowBackground(EmptyView())
	}

	@ViewBuilder
	private func _referralSection() -> some View {
		Section {
			Text(AppMasterProfile.referralLink)
				.font(.footnote.monospaced())
				.foregroundStyle(.secondary)
				.textSelection(.enabled)

			Button {
				UIPasteboard.general.string = AppMasterProfile.referralLink
				UINotificationFeedbackGenerator().notificationOccurred(.success)
				_didCopyLink = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
					_didCopyLink = false
				}
			} label: {
				Label {
					Text(.localized(_didCopyLink ? "Copied" : "Copy Link"))
				} icon: {
					Image(systemName: _didCopyLink ? "checkmark" : "doc.on.doc")
				}
			}

			ShareLink(item: AppMasterProfile.referralLink) {
				Label(.localized("Share Link"), systemImage: "square.and.arrow.up")
			}
		} header: {
			Text(.localized("Referral Link"))
		} footer: {
			Text(.localized("Share this link with other people."))
		}
	}
}
