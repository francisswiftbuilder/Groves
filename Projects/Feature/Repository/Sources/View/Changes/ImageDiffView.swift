import AppKit
import DomainGitInterface
import SwiftUI

struct ImageDiffView: View {
	@State private var beforeImage: NSImage?
	@State private var afterImage: NSImage?
	@State private var isDecoding = true
	@State private var zoom = 1.0
	let diff: GitImageDiff
	let beforeTitle: String
	let afterTitle: String

	var body: some View {
		Group {
			if isDecoding {
				LoadingStateView(
					title: "Loading Images",
					message: "Preparing both versions for comparison."
				)
			} else {
				ScrollView(.horizontal) {
					HStack(spacing: 10) {
						DiffImagePane(
							title: beforeTitle,
							image: beforeImage,
							byteCount: diff.before?.count,
							zoom: zoom,
							unavailableMessage: "No \(beforeTitle) Image"
						)
						.frame(minWidth: 280, maxWidth: .infinity)

						DiffImagePane(
							title: afterTitle,
							image: afterImage,
							byteCount: diff.after?.count,
							zoom: zoom,
							unavailableMessage: "No \(afterTitle) Image"
						)
						.frame(minWidth: 280, maxWidth: .infinity)
					}
					.padding(12)
					.containerRelativeFrame(.horizontal)
				}
			}
		}
		.safeAreaInset(edge: .top) {
			zoomControls
		}
		.task(id: diff) {
			isDecoding = true
			async let requestedBeforeImage = DiffImageDecoder.decode(diff.before)
			async let requestedAfterImage = DiffImageDecoder.decode(diff.after)
			beforeImage = await requestedBeforeImage
			afterImage = await requestedAfterImage
			isDecoding = false
		}
	}

	private var zoomControls: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Label("Image Comparison", systemImage: "photo.on.rectangle.angled")
					.font(.caption.weight(.medium))
				Spacer(minLength: 12)
				Button("Zoom Out", systemImage: "minus.magnifyingglass") {
					zoom = max(zoom - 0.25, 0.25)
				}
				.labelStyle(.iconOnly)
				.disabled(zoom <= 0.25)
				.help("Zoom Out")

				Slider(value: $zoom, in: 0.25...3, step: 0.25)
					.frame(width: 110)
					.accessibilityLabel("Image Zoom")
					.accessibilityValue("\(Int(zoom * 100)) percent")

				Button("Zoom In", systemImage: "plus.magnifyingglass") {
					zoom = min(zoom + 0.25, 3)
				}
				.labelStyle(.iconOnly)
				.disabled(zoom >= 3)
				.help("Zoom In")

				Button("Fit", systemImage: "arrow.down.right.and.arrow.up.left") {
					zoom = 1
				}
				.labelStyle(.iconOnly)
				.help("Fit Images")
			}
			.controlSize(.small)
			.padding(.horizontal, 12)
			.frame(height: 36)
			.background(.bar)
			Divider()
		}
	}
}
