import DomainGitInterface
import SwiftUI

struct ChangeRow: View {
	let change: WorkingTreeChange
	let state: GitFileState
	let isStaged: Bool

	var body: some View {
		HStack(spacing: 8) {
			ChangeFileIcon(path: change.path)

			VStack(alignment: .leading, spacing: 2) {
				Text(URL(fileURLWithPath: change.path).lastPathComponent)
					.lineLimit(1)
					.truncationMode(.middle)
				if change.isStaged, change.hasWorkingTreeChange {
					Text("Partially Staged")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 8)

			Text(state.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(state.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.padding(.trailing, 12)
		.help(change.path)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(
			"\(URL(fileURLWithPath: change.path).lastPathComponent), \(state.inspectorTitle), \(isStaged ? "Staged" : "Unstaged")"
		)
		.accessibilityValue(
			Text(change.isStaged && change.hasWorkingTreeChange ? "Partially Staged" : ""))
	}
}
