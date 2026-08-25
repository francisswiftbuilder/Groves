import DomainGitInterface
import SwiftUI

struct DiffView: View {
	@StateObject private var viewerModel = DiffViewerModel()
	@Binding var options: GitDiffOptions
	@Binding var presentationMode: DiffPresentationMode
	let diff: String
	let imageDiff: GitImageDiff?
	let changedFileCount: Int
	let fileName: String?
	let filePath: String?
	let fileState: GitFileState?
	let fileActionTitle: String?
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isLoadingDiff: Bool
	let isApplyingAction: Bool
	let onOptionsChanged: () -> Void
	let onApplyFileAction: () -> Void
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if !diff.isEmpty || imageDiff != nil {
				diffFooter
			}
		}
		.task(id: diff) {
			await viewerModel.update(diff: diff)
		}
	}

	private var diffFooter: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files with changes")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				if !isImageFile {
					DiffStatisticsView(document: viewerModel.document)
				}
			}
			.font(.caption)
			.padding(.horizontal, 16)
			.frame(height: 40)
		}
		.background(.bar)
	}

	@ViewBuilder
	private var diffHeader: some View {
		if let fileName {
			HStack(spacing: 10) {
				if let fileState {
					GitStatusBadge(state: fileState)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(fileName)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					if let filePath {
						Text(filePath)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 12)

				if !diff.isEmpty, imageDiff == nil {
					DiffStatisticsView(document: viewerModel.document)
				}

				if !isImageFile {
					DiffOptionsMenu(
						options: $options,
						presentationMode: $presentationMode,
						onChange: onOptionsChanged
					)
				}

				if let fileActionTitle {
					Button(fileActionTitle, action: onApplyFileAction)
						.buttonStyle(.bordered)
						.controlSize(.small)
						.disabled(isApplyingAction || isLoadingDiff)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		} else {
			HStack {
				Text("Diff")
					.font(.subheadline.weight(.semibold))
				Spacer()
				DiffOptionsMenu(
					options: $options,
					presentationMode: $presentationMode,
					onChange: onOptionsChanged
				)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
	}

	@ViewBuilder
	private var diffContent: some View {
		if isApplyingAction {
			ProgressView()
				.controlSize(.regular)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.accessibilityLabel("Applying diff change")
		} else if isLoadingDiff || viewerModel.isParsing {
			LoadingStateView(
				title: "Loading Diff",
				message: "Reading the selected file changes."
			)
		} else if let imageDiff {
			ImageDiffView(
				diff: imageDiff,
				beforeTitle: "Previous",
				afterTitle: "Current"
			)
		} else if isImageFile {
			EmptyStateView(
				title: "Image Preview Unavailable",
				message: "Neither version contains a supported image.",
				systemImage: "photo.badge.exclamationmark"
			)
		} else if diff.isEmpty {
			EmptyStateView(
				title: "No Diff Selected",
				message: "Select a tracked text change to inspect its diff.",
				systemImage: "doc.text.magnifyingglass"
			)
		} else if viewerModel.document.lines.isEmpty {
			EmptyStateView(
				title: "No Text Diff",
				message: "This file has no text changes to display.",
				systemImage: "doc"
			)
		} else {
			DiffViewer(
				document: viewerModel.document,
				presentationMode: presentationMode,
				filePath: filePath,
				lineAction: lineAction,
				hunkActions: hunkActions,
				isApplyingAction: isApplyingAction,
				onApplyLine: onApplyLine,
				onApplyHunk: onApplyHunk
			)
		}
	}

	private var isImageFile: Bool {
		filePath.map(DiffImageFileSupport.isSupported) == true
	}
}
