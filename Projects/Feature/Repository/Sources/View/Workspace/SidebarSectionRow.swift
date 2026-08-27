import DomainGitInterface
import FeatureRepositoryInterface
import SwiftUI

struct SidebarSectionRow: View {
	let section: WorkspaceSection
	let badgeCount: Int?

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: section.systemImage)
				.font(.system(size: 13))
				.symbolRenderingMode(.hierarchical)
				.frame(width: 16)
				.accessibilityHidden(true)

			Text(section.title)
				.lineLimit(1)

			Spacer(minLength: 8)

			if let badgeCount, badgeCount > 0 {
				Text(badgeCount, format: .number)
					.font(.caption)
					.foregroundStyle(.secondary)
					.monospacedDigit()
			}
		}
		.frame(minHeight: 22)
		.contentShape(.rect)
	}
}
