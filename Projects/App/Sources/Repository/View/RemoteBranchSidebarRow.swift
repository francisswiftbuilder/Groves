import DomainGitInterface
import SwiftUI

struct RemoteBranchSidebarRow: View {
	let branch: GitRemoteBranch
	var showsRemoteName = false

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: "arrow.triangle.branch",
			accessory: showsRemoteName ? branch.remoteName : nil
		)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(branch.fullName)
	}
}
