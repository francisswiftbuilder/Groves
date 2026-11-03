import DomainGitInterface
import SwiftUI

struct AmendChangeRow: View {
	let change: GitAmendChange

	var body: some View {
		HStack(spacing: 8) {
			ChangeFileIcon(path: change.path)

			Text(URL(fileURLWithPath: change.path).lastPathComponent)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer(minLength: 8)

			Text(change.state.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(change.state.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.padding(.trailing, 12)
		.help(change.path)
		.accessibilityElement(children: .combine)
	}
}
