import DomainGitInterface
import SwiftUI

struct CommitChangedFileRow: View {
	let file: CommitDiffFile

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "doc")
				.foregroundStyle(.secondary)
				.frame(width: 14)
			Text(file.path)
				.font(.caption)
				.multilineTextAlignment(.leading)
				.lineLimit(2)
			Spacer(minLength: 6)
			Text("+\(file.additions)")
				.foregroundStyle(.green)
			Text("−\(file.deletions)")
				.foregroundStyle(.red)
		}
		.font(.caption.monospacedDigit())
		.padding(.horizontal, 6)
		.padding(.vertical, 5)
		.contentShape(.rect)
	}
}
