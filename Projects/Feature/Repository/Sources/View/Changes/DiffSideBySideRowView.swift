import DomainGitInterface
import SwiftUI

struct DiffSideBySideRowView: View {
	let row: DiffSideBySideRow
	let paneWidth: CGFloat
	let filePath: String?
	let searchText: String
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isLoading: Bool
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		Group {
			if let line = row.fullWidthLine {
				DiffLineView(
					line: line,
					filePath: filePath,
					searchText: searchText,
					showsOldLineNumbers: false,
					showsNewLineNumbers: false,
					lineAction: lineAction,
					hunkActions: hunkActions,
					isLoading: isLoading,
					onApplyLine: onApplyLine,
					onApplyHunk: onApplyHunk
				)
				.frame(width: paneWidth * 2 + 28, alignment: .leading)
				.clipped()
			} else {
				HStack(alignment: .top, spacing: 0) {
					DiffSideBySidePane(
						line: row.oldLine,
						filePath: filePath,
						searchText: searchText,
						isOld: true
					)
					.frame(width: paneWidth)
					.clipped()

					lineActionButton

					DiffSideBySidePane(
						line: row.newLine,
						filePath: filePath,
						searchText: searchText,
						isOld: false
					)
					.frame(width: paneWidth)
					.clipped()
				}
				.contextMenu { lineContextMenu }
			}
		}
	}

	@ViewBuilder
	private var lineActionButton: some View {
		if let actionLine = row.actionLine,
			let selection = actionLine.selection,
			let lineAction
		{
			Button {
				onApplyLine(selection, lineAction)
			} label: {
				Image(systemName: lineAction.systemImage)
					.frame(width: 20, height: 20)
			}
			.buttonStyle(.borderless)
			.tint(lineAction.tint)
			.frame(width: 28, height: 20)
			.disabled(isLoading)
			.help(lineAction.title)
			.accessibilityLabel(lineAction.title)
		} else {
			Divider()
				.frame(width: 28)
				.accessibilityHidden(true)
		}
	}

	@ViewBuilder
	private var lineContextMenu: some View {
		if let actionLine = row.actionLine,
			let selection = actionLine.selection,
			let lineAction
		{
			Button(lineAction.title, systemImage: lineAction.systemImage) {
				onApplyLine(selection, lineAction)
			}
			.disabled(isLoading)
		}
	}
}
