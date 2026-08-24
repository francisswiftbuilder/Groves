import DomainGitInterface
import SwiftUI

struct DiffView: View {
	let diff: String
	let changedFileCount: Int
	let fileName: String?
	let filePath: String?
	let fileState: GitFileState?
	let fileActionTitle: String?
	let lineAction: GitDiffLineAction?
	let isLoadingDiff: Bool
	let isApplyingAction: Bool
	let onApplyFileAction: () -> Void
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void

	var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if !diff.isEmpty {
				diffFooter
			}
		}
	}

	private var diffFooter: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files with changes")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				DiffStatisticsView(diffLines: diffLines)
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

				if !diff.isEmpty {
					DiffStatisticsView(diffLines: diffLines)
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
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
	}

	@ViewBuilder
	private var diffContent: some View {
		if isLoadingDiff {
			LoadingStateView(
				title: "Loading Diff",
				message: "Reading the selected file changes."
			)
		} else if diff.isEmpty {
			EmptyStateView(
				title: "No Diff Selected",
				message: "Select a tracked text change to inspect its diff.",
				systemImage: "doc.text.magnifyingglass"
			)
		} else if diffLines.isEmpty {
			EmptyStateView(
				title: "Empty File",
				message: "This file has no content.",
				systemImage: "doc"
			)
		} else {
			GeometryReader { geometry in
				ScrollView([.horizontal, .vertical]) {
					VStack(alignment: .leading, spacing: 0) {
						ForEach(diffLines) { line in
							DiffLineView(
								line: line,
								showsOldLineNumbers: showsOldLineNumbers,
								showsNewLineNumbers: showsNewLineNumbers,
								action: lineAction,
								isLoading: isApplyingAction,
								onApply: onApplyLine
							)
						}
					}
					.padding(.vertical, 8)
					.frame(minWidth: max(geometry.size.width, 0), alignment: .leading)
				}
				.defaultScrollAnchor(.topLeading)
			}
		}
	}

	private var diffLines: [DiffLine] {
		DiffParser.parseSourceLines(diff)
	}

	private var showsOldLineNumbers: Bool {
		diffLines.contains { $0.oldLineNumber != nil }
	}

	private var showsNewLineNumbers: Bool {
		diffLines.contains { $0.newLineNumber != nil }
	}

}
