import DomainGitInterface
import SwiftUI

struct BranchSidebarRow: View {
	let branch: GitBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch",
			accessory: trackingAccessory
		)
	}

	private var trackingAccessory: String? {
		var components: [String] = []
		if let upstream = branch.upstream {
			components.append(upstream)
		} else if branch.isCurrent {
			components.append("No Upstream")
		}
		if branch.aheadCount > 0 {
			components.append("↑\(branch.aheadCount)")
		}
		if branch.behindCount > 0 {
			components.append("↓\(branch.behindCount)")
		}
		return components.isEmpty ? nil : components.joined(separator: " · ")
	}
}
