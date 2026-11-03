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
		.help(details)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(branch.isCurrent ? "\(branch.name), current branch" : branch.name)
		.accessibilityValue(trackingDescription)
	}

	private var trackingAccessory: String? {
		var components: [String] = []
		if branch.aheadCount > 0 { components.append("↑\(branch.aheadCount)") }
		if branch.behindCount > 0 { components.append("↓\(branch.behindCount)") }
		return components.isEmpty ? nil : components.joined(separator: " ")
	}

	private var details: String {
		let tracking = branch.upstream.map { "Tracks \($0)" } ?? "No upstream branch"
		return [branch.name, tracking, trackingDescription].filter { !$0.isEmpty }.joined(
			separator: "\n")
	}

	private var trackingDescription: String {
		var components: [String] = []
		if branch.aheadCount > 0 { components.append("\(branch.aheadCount) commits ahead") }
		if branch.behindCount > 0 { components.append("\(branch.behindCount) commits behind") }
		return components.joined(separator: ", ")
	}
}
