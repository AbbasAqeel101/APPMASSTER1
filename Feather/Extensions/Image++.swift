//
//  Image+appIconStyle.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import SwiftUI

extension Image {
	/// Applies a standard icon style with firmware-aware corner radius
	func appIconStyle(
		size: CGFloat = 56,
		lineWidth: CGFloat = 1,
		isCircle: Bool = false,
		background: Color = .clear
	) -> some View {
		var multiplier: CGFloat = 0.2337
		if #available(iOS 26.0, *) {
			multiplier = 0.2677
		}
		
		let radius = isCircle ? (size / 2) : (size * multiplier)
		
		return self.resizable()
			// Circular avatars/badges must always fill the shape edge-to-edge, even
			// if the source asset isn't perfectly square — scaledToFit can leave
			// visible gaps inside the circle. Square app-icon assets keep fitting
			// so nothing gets cropped.
			.aspectRatio(contentMode: isCircle ? .fill : .fit)
			.frame(width: size, height: size)
			.clipped()
			.background(
				RoundedRectangle(cornerRadius: radius, style: .continuous)
					.fill(background)
			)
			.overlay {
				RoundedRectangle(cornerRadius: radius, style: .continuous)
					.strokeBorder(Color.primary.opacity(0.15), lineWidth: lineWidth)
			}
			.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
	}
}
