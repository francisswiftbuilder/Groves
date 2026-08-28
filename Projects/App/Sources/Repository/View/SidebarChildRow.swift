import DomainGitInterface
import SwiftUI

struct SidebarChildRow: View {
	let title: String
	let systemImage: String
	let accessory: String?

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.font(.system(size: 11))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.frame(width: 14)

			Text(title)
				.lineLimit(1)

			Spacer(minLength: 6)

			if let accessory {
				Text(accessory)
					.font(.caption2)
					.foregroundStyle(.tertiary)
					.lineLimit(1)
			}
		}
		.frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
		.contentShape(.rect)
	}
}
