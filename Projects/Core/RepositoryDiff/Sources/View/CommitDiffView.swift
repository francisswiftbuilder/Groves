import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

public struct CommitDiffView: View {
	@StateObject private var viewerModel = DiffViewerViewModel()
	private let searchModel: RepositorySearchViewModel
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
		searchModel: RepositorySearchViewModel,
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
		self.searchModel = searchModel
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
			if file != nil {
				diffFooter
			}
		}
		.task(id: viewerInput) {
			await viewerModel.update(input: viewerInput)
		}
	}

	private var diffFooter: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files changed")
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
		if file != nil {
			VStack(alignment: .leading, spacing: 12) {
				HStack(spacing: 8) {
					Text(displayedFilePath.replacingOccurrences(of: "/", with: " / "))
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
						DiffStatisticsView(document: displayedDocument)
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
		if isLoading {
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
			} else if viewerModel.presentation == nil {
				LoadingStateView(
					title: "Loading Commit Diff",
					message: "Reading the files changed by this commit."
				)
			} else if viewerModel.presentation?.document.lines.isEmpty == true {
				EmptyStateView(
					title: "No Text Diff",
					message: "This commit changed a file without a text diff.",
					systemImage: "doc"
				)
			} else if let presentation = viewerModel.presentation {
				DiffViewer(
					searchModel: searchModel,
					document: presentation.document,
					sideBySideRows: presentation.sideBySideRows,
					presentationMode: presentationMode,
					filePath: presentation.input.filePath,
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

	private var viewerInput: DiffViewerViewModel.Input {
		DiffViewerViewModel.Input(sourceID: file?.id, filePath: file?.path, diff: file?.diff ?? "")
	}

	private var displayedDocument: DiffDocument {
		viewerModel.presentation?.document ?? .empty
	}

	private var displayedFilePath: String {
		if currentFileIsImage || isLoading {
			return file?.path ?? ""
		}
		return viewerModel.presentation?.input.filePath ?? file?.path ?? ""
	}

	private var currentFileIsImage: Bool {
		file.map { DiffImageFileSupport.isSupported(path: $0.path) } == true
	}

	private var isImageFile: Bool {
		DiffImageFileSupport.isSupported(path: displayedFilePath)
	}
}
