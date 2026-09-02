import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

public struct ImageDiffView: View {
	@StateObject private var viewModel: ImageDiffViewModel
	@State private var zoom = 1.0
	let diff: GitImageDiff
	let beforeTitle: String
	let afterTitle: String

	public init(diff: GitImageDiff, beforeTitle: String, afterTitle: String) {
		_viewModel = StateObject(
			wrappedValue: ImageDiffViewModel(
				dependencies: .init { data in
					await DiffImageDecoder.decode(data)
				}
			)
		)
		self.diff = diff
		self.beforeTitle = beforeTitle
		self.afterTitle = afterTitle
	}

	public var body: some View {
		Group {
			switch viewModel.state {
			case .idle, .loading:
				LoadingStateView(
					title: "Loading Images",
					message: "Preparing both versions for comparison."
				)
			case .loaded(let presentation):
				ScrollView(.horizontal) {
					HStack(spacing: 10) {
						DiffImagePane(
							title: beforeTitle,
							image: presentation.beforeImage,
							byteCount: diff.before?.count,
							decodingFailed: presentation.beforeDecodingFailed,
							zoom: zoom,
							unavailableMessage: "No \(beforeTitle) Image"
						)
						.frame(minWidth: 280, maxWidth: .infinity)

						DiffImagePane(
							title: afterTitle,
							image: presentation.afterImage,
							byteCount: diff.after?.count,
							decodingFailed: presentation.afterDecodingFailed,
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
		.onAppear {
			viewModel.onAppear(diff: diff)
		}
		.onChange(of: diff) { _, diff in
			viewModel.didChangeDiff(diff)
		}
		.onDisappear {
			viewModel.onDisappear()
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
