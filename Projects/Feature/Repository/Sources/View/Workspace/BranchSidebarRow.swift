import DomainGitInterface
import SwiftUI

struct BranchSidebarRow: View {
	let branch: GitBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch",
			accessory: branch.isCurrent ? "Current" : nil
		)
	}
}
