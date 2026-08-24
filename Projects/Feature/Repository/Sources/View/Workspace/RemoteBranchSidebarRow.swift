import DomainGitInterface
import SwiftUI

struct RemoteBranchSidebarRow: View {
	let branch: GitRemoteBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: "arrow.triangle.branch",
			accessory: nil
		)
	}
}
