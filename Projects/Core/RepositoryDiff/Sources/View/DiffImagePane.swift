import AppKit
import CoreRepositoryUI
import SwiftUI

struct DiffImagePane: View {
	let title: String
	let image: NSImage?
	let byteCount: Int?
	let decodingFailed: Bool
	let zoom: CGFloat
	let unavailableMessage: String

	var body: some View {
		VStack(spacing: 0) {
			if let image {
				GeometryReader { geometry in
					ScrollView([.horizontal, .vertical]) {
						Image(nsImage: image)
							.resizable()
							.interpolation(.high)
							.frame(
								width: fittedSize(in: geometry.size, image: image).width * zoom,
								height: fittedSize(in: geometry.size, image: image).height * zoom
							)
							.padding(16)
							.accessibilityLabel("\(title) image")
							.accessibilityValue(
								"\(Int(image.size.width)) by \(Int(image.size.height)) pixels"
							)
							.frame(
								minWidth: geometry.size.width,
								minHeight: geometry.size.height,
								alignment: .center
							)
					}
					.defaultScrollAnchor(.center)
				}
			} else if decodingFailed {
				EmptyStateView(title: "Unsupported Image", systemImage: "photo.badge.exclamationmark")
			} else {
				EmptyStateView(title: unavailableMessage, systemImage: "photo.badge.exclamationmark")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .top, spacing: 0) {
			VStack(spacing: 0) {
				HStack(spacing: 8) {
					Text(title)
						.font(.caption.weight(.semibold))
					Spacer(minLength: 8)
					if let image {
						Text("\(Int(image.size.width)) × \(Int(image.size.height))")
							.foregroundStyle(.secondary)
					}
					if let byteCount {
						Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
							.foregroundStyle(.secondary)
					}
				}
				.font(.caption)
				.padding(.horizontal, 10)
				.frame(height: 30)

				Divider()
			}
		}
	}

	private func fittedSize(in availableSize: CGSize, image: NSImage) -> CGSize {
		guard image.size.width > 0, image.size.height > 0 else { return .zero }
		let availableWidth = max(availableSize.width - 32, 1)
		let availableHeight = max(availableSize.height - 32, 1)
		let scale = min(
			availableWidth / image.size.width,
			availableHeight / image.size.height,
			1
		)
		return CGSize(width: image.size.width * scale, height: image.size.height * scale)
	}
}
