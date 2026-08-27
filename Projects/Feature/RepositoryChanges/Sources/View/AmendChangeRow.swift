import DomainGitInterface
import SwiftUI

struct AmendChangeRow: View {
	let change: GitAmendChange
	let onUnstage: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Toggle(
				"",
				isOn: Binding(
					get: { true },
					set: { isIncluded in
						if !isIncluded {
							onUnstage()
						}
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

			Text(change.state.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(change.state.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}
