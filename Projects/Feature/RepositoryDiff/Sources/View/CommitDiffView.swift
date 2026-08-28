import CoreRepositoryUI
import DomainGitInterface
import FeatureRepositoryInterface
import SwiftUI

public struct CommitDiffView: View {
	@StateObject private var viewerModel = DiffViewerViewModel()
	@Binding var options: GitDiffOptions
	@Binding var presentationMode: DiffPresentationMode
	let file: CommitDiffFile?
	let imageDiff: GitImageDiff?
	let beforeImageTitle: String
	let afterImageTitle: String
	let changedFileCount: Int
	let isLoading: Bool
	let onOptionsChanged: () -> Void

	public init(
		options: Binding<GitDiffOptions>,
		presentationMode: Binding<DiffPresentationMode>,
		file: CommitDiffFile?,
		imageDiff: GitImageDiff?,
		beforeImageTitle: String,
		afterImageTitle: String,
		changedFileCount: Int,
		isLoading: Bool,
		onOptionsChanged: @escaping () -> Void
	) {
		_options = options
		_presentationMode = presentationMode
		self.file = file
		self.imageDiff = imageDiff
		self.beforeImageTitle = beforeImageTitle
		self.afterImageTitle = afterImageTitle
		self.changedFileCount = changedFileCount
		self.isLoading = isLoading
		self.onOptionsChanged = onOptionsChanged
	}

	public var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if let file {
				diffFooter(file: file)
			}
		}
		.task(id: file?.diff) {
			await viewerModel.update(diff: file?.diff ?? "")
		}
	}

	private func diffFooter(file: CommitDiffFile) -> some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files changed")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				if !isImageFile {
					CommitDiffStatistics(file: file)
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
		if let file {
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 8) {
					Text(file.path.replacingOccurrences(of: "/", with: " / "))
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(1)
					Spacer(minLength: 8)
					if !isImageFile {
						DiffOptionsMenu(
							options: $options,
							presentationMode: $presentationMode,
							onChange: onOptionsChanged
						)
					}
				}

				HStack(spacing: 8) {
					Text("File changed")
						.font(.subheadline.weight(.medium))
					Spacer()
					if !isImageFile {
						CommitDiffStatistics(file: file)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		} else {
			HStack {
				Text("Changes")
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
		if isLoading || viewerModel.isParsing {
			LoadingStateView(
				title: "Loading Commit Diff",
				message: "Reading the files changed by this commit."
			)
		} else if file != nil {
			if let imageDiff {
				ImageDiffView(
					diff: imageDiff,
					beforeTitle: beforeImageTitle,
					afterTitle: afterImageTitle
				)
			} else if isImageFile {
				EmptyStateView(
					title: "Image Preview Unavailable",
					message: "Neither revision contains a supported image.",
					systemImage: "photo.badge.exclamationmark"
				)
			} else if viewerModel.document.lines.isEmpty {
				EmptyStateView(
					title: "No Text Diff",
					message: "This commit changed a file without a text diff.",
					systemImage: "doc"
				)
			} else {
				DiffViewer(
					document: viewerModel.document,
					sideBySideRows: viewerModel.sideBySideRows,
					presentationMode: presentationMode,
					filePath: file?.path,
					lineAction: nil,
					hunkActions: [],
					isApplyingAction: false,
					onApplyLine: { _, _ in },
					onApplyHunk: { _, _ in }
				)
			}
		} else {
			EmptyStateView(
				title: "No File Selected",
				message: "Select a changed file to inspect this commit.",
				systemImage: "doc.text.magnifyingglass"
			)
		}
	}

	private var isImageFile: Bool {
		file.map { DiffImageFileSupport.isSupported(path: $0.path) } == true
	}
}
