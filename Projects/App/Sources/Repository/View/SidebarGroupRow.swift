import DomainGitInterface
import SwiftUI

struct SidebarGroupRow: View {
	let title: String
	let systemImage: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: systemImage)
				.font(.system(size: 13))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 16)
				.accessibilityHidden(true)

			Text(title)
				.lineLimit(1)
		}
		.frame(minHeight: 22)
		.contentShape(.rect)
	}
}
