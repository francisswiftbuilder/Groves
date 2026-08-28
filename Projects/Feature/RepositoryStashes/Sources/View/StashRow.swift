import DomainGitInterface
import SwiftUI

struct StashRow: View {
	let stash: GitStash

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "archivebox.fill")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.purple)
				.frame(width: 20)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(stash.subject)
					.lineLimit(1)

				HStack(spacing: 8) {
					Text(stash.reference)
					Text(stash.hash.prefix(7))
						.font(.system(.caption, design: .monospaced))
					if let date = stash.date {
						Text(date, style: .relative)
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}
