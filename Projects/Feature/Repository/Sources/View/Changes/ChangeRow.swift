import DomainGitInterface
import SwiftUI

struct ChangeRow: View {
	let change: WorkingTreeChange
	let state: GitFileState
	let isStaged: Bool
	let onSetStaged: (Bool) -> Void

	var body: some View {
		HStack(spacing: 8) {
			Toggle(
				"",
				isOn: Binding(
					get: { isStaged },
					set: { isStaged in
						onSetStaged(isStaged)
					}
				)
			)
			.labelsHidden()
			.toggleStyle(.checkbox)
			.controlSize(.small)

			ChangeFileIcon(path: change.path)

			Text(URL(fileURLWithPath: change.path).lastPathComponent)
				.lineLimit(1)

			Spacer(minLength: 8)

			Text(state.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(state.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}
