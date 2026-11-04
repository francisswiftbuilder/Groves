import SwiftUI

struct SidebarSectionRow: View {
	let section: WorkspaceSection
	let title: String?
	let badgeCount: Int?

	init(section: WorkspaceSection, title: String? = nil, badgeCount: Int? = nil) {
		self.section = section
		self.title = title
		self.badgeCount = badgeCount
	}

	var body: some View {
		Label(title ?? section.title, systemImage: section.systemImage)
			.lineLimit(1)
			.badge(badgeCount ?? 0)
	}
}
