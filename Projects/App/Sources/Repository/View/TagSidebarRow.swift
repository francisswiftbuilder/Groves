import DomainGitInterface
import SwiftUI

struct TagSidebarRow: View {
	let tag: GitTag

	var body: some View {
		SidebarChildRow(title: tag.name, systemImage: "tag", accessory: nil)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}
