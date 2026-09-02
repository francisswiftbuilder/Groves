import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

public struct DiffView: View {
	@StateObject private var viewerModel = DiffViewerViewModel()
	private let searchModel: RepositorySearchViewModel
	@Binding var options: GitDiffOptions
	@Binding var presentationMode: DiffPresentationMode
	let sourceID: String?
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

	public init(
		searchModel: RepositorySearchViewModel,
		options: Binding<GitDiffOptions>,
		presentationMode: Binding<DiffPresentationMode>,
		sourceID: String?,
		diff: String,
		imageDiff: GitImageDiff?,
		changedFileCount: Int,
		fileName: String?,
		filePath: String?,
		fileState: GitFileState?,
		fileActionTitle: String?,
		lineAction: GitDiffLineAction?,
		hunkActions: [GitDiffHunkAction],
		isLoadingDiff: Bool,
		isApplyingAction: Bool,
		onOptionsChanged: @escaping () -> Void,
		onApplyFileAction: @escaping () -> Void,
		onApplyLine: @escaping (GitDiffLineSelection, GitDiffLineAction) -> Void,
		onApplyHunk: @escaping (GitDiffHunkSelection, GitDiffHunkAction) -> Void
	) {
		self.searchModel = searchModel
		_options = options
		_presentationMode = presentationMode
		self.sourceID = sourceID
		self.diff = diff
		self.imageDiff = imageDiff
		self.changedFileCount = changedFileCount
		self.fileName = fileName
		self.filePath = filePath
		self.fileState = fileState
		self.fileActionTitle = fileActionTitle
		self.lineAction = lineAction
		self.hunkActions = hunkActions
		self.isLoadingDiff = isLoadingDiff
		self.isApplyingAction = isApplyingAction
		self.onOptionsChanged = onOptionsChanged
		self.onApplyFileAction = onApplyFileAction
		self.onApplyLine = onApplyLine
		self.onApplyHunk = onApplyHunk
	}

	public var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			if options.ignoresWhitespace, !diff.isEmpty {
				partialActionsDisabledBanner
			}
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if !diff.isEmpty || imageDiff != nil {
				diffFooter
			}
		}
		.task(id: viewerInput) {
			await viewerModel.update(input: viewerInput)
		}
	}

	private var partialActionsDisabledBanner: some View {
		HStack(spacing: 8) {
			Image(systemName: "line.3.horizontal.decrease.circle")
				.foregroundStyle(.secondary)
			Text("Line and hunk actions are unavailable while Ignore All Whitespace is enabled.")
				.font(.caption)
				.foregroundStyle(.secondary)
			Spacer(minLength: 8)
			Button("Show Whitespace") {
				options.ignoresWhitespace = false
				onOptionsChanged()
			}
			.controlSize(.small)
		}
		.padding(.horizontal, 12)
		.frame(minHeight: 36)
		.background(Color.accentColor.opacity(0.08))
	}

	private var diffFooter: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files with changes")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				if !isImageFile {
					DiffStatisticsView(document: displayedDocument)
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
		if let displayedFileName {
			HStack(spacing: 10) {
				if displaysCurrentInput, let fileState {
					GitStatusBadge(state: fileState)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(displayedFileName)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					if let displayedFilePath {
						Text(displayedFilePath)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 12)

				if !displayedDocument.lines.isEmpty, imageDiff == nil {
					DiffStatisticsView(document: displayedDocument)
				}

				if !isImageFile {
					DiffOptionsMenu(
						options: $options,
						presentationMode: $presentationMode,
						onChange: onOptionsChanged
					)
				}

				if displaysCurrentInput, let fileActionTitle {
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
		} else if isLoadingDiff && !displaysCurrentSource {
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
		} else if viewerModel.presentation == nil {
			LoadingStateView(
				title: "Loading Diff",
				message: "Reading the selected file changes."
			)
		} else if displayedDocument.lines.isEmpty {
			EmptyStateView(
				title: "No Text Diff",
				message: "This file has no text changes to display.",
				systemImage: "doc"
			)
		} else if let presentation = viewerModel.presentation {
			DiffViewer(
				searchModel: searchModel,
				document: presentation.document,
				sideBySideRows: presentation.sideBySideRows,
				presentationMode: presentationMode,
				filePath: presentation.input.filePath,
				lineAction: allowsPartialActions ? lineAction : nil,
				hunkActions: allowsPartialActions ? hunkActions : [],
				isApplyingAction: isApplyingAction,
				onApplyLine: { selection, action in
					guard allowsPartialActions else { return }
					onApplyLine(selection, action)
				},
				onApplyHunk: { selection, action in
					guard allowsPartialActions else { return }
					onApplyHunk(selection, action)
				}
			)
			.id(presentation.revision)
		}
	}

	private var viewerInput: DiffViewerViewModel.Input {
		DiffViewerViewModel.Input(sourceID: sourceID, filePath: filePath, diff: diff)
	}

	private var displaysCurrentInput: Bool {
		viewerModel.canInteract(with: viewerInput)
	}

	private var displaysCurrentSource: Bool {
		viewerModel.presentation?.input.sourceID == sourceID
	}

	private var allowsPartialActions: Bool {
		displaysCurrentInput && !isLoadingDiff
	}

	private var displayedDocument: DiffDocument {
		viewerModel.presentation?.document ?? .empty
	}

	private var displayedFilePath: String? {
		if currentFileIsImage || (isLoadingDiff && !displaysCurrentSource) {
			return filePath
		}
		return viewerModel.presentation?.input.filePath ?? filePath
	}

	private var displayedFileName: String? {
		displayedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fileName
	}

	private var currentFileIsImage: Bool {
		filePath.map(DiffImageFileSupport.isSupported) == true
	}

	private var isImageFile: Bool {
		displayedFilePath.map(DiffImageFileSupport.isSupported) == true
	}
}
