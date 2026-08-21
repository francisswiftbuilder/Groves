import DomainGitInterface
import SwiftUI

struct RepositorySidebar: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	let repositoryID: RepositoryTab.ID
	@Binding var selectedItem: RepositorySidebarSelection?
	@State private var expandedGroups: Set<RepositorySidebarGroup> = []

	var body: some View {
		List(selection: $selectedItem) {
			RepositoryNavigationRows(
				workspace: viewModel,
				repositoryID: repositoryID,
				expandedGroups: $expandedGroups
			)
			.padding(.horizontal, 10)
		}
		.listStyle(.sidebar)
		.contextMenu(forSelectionType: RepositorySidebarSelection.self) { selections in
			sidebarContextMenu(for: selections)
		} primaryAction: { selections in
			performPrimaryAction(for: selections)
		}
		.onAppear {
			expandDefaultGroups(repositoryID: repositoryID)
			if let selectedSection = viewModel.selectedSection {
				expandGroupIfNeeded(selectedSection, repositoryID: repositoryID)
			}
		}
	}

	@ViewBuilder
	private func sidebarContextMenu(
		for selections: Set<RepositorySidebarSelection>
	) -> some View {
		if selections.count == 1,
			let selection = selections.first,
			selection.repositoryID == repositoryID
		{
			switch selection {
			case .branch(_, let id):
				if let branch = viewModel.branches.first(where: { $0.id == id }) {
					Button("Switch to \(branch.name)", systemImage: "arrow.triangle.branch") {
						selectBranch(branch)
						viewModel.didRequestSwitchBranch()
					}
					.disabled(branch.isCurrent)

					Button("Delete Branch", systemImage: "trash", role: .destructive) {
						selectBranch(branch)
						viewModel.didRequestDeleteBranch()
					}
					.disabled(branch.isCurrent)
				}
			case .stash(_, let id):
				if let stash = viewModel.stashes.first(where: { $0.id == id }) {
					Button("Apply Stash", systemImage: "arrow.down.doc") {
						selectStash(stash)
						viewModel.didRequestApplyStash()
					}

					Button("Pop Stash", systemImage: "arrow.up.doc") {
						selectStash(stash)
						viewModel.didRequestPopStash()
					}

					Divider()

					Button("Delete Stash", systemImage: "trash", role: .destructive) {
						selectStash(stash)
						viewModel.didRequestDropStash()
					}
				}
			case .section, .remote, .remoteBranch, .tag:
				EmptyView()
			}
		}
	}

	private func performPrimaryAction(
		for selections: Set<RepositorySidebarSelection>
	) {
		guard
			selections.count == 1,
			let selection = selections.first,
			case .branch(_, let id) = selection,
			selection.repositoryID == repositoryID,
			let branch = viewModel.branches.first(where: { $0.id == id })
		else { return }

		selectBranch(branch)
		viewModel.didRequestSwitchBranch()
	}

	private func selectBranch(_ branch: GitBranch) {
		selectedItem = .branch(repositoryID: repositoryID, id: branch.id)
		viewModel.selectedBranchID = branch.id
	}

	private func selectStash(_ stash: GitStash) {
		selectedItem = .stash(repositoryID: repositoryID, id: stash.id)
		viewModel.selectedStashID = stash.id
	}

	private func expandGroupIfNeeded(
		_ section: WorkspaceSection,
		repositoryID: RepositoryTab.ID
	) {
		guard let kind = RepositorySidebarGroupKind(section: section) else { return }
		expandedGroups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
	}

	private func expandDefaultGroups(repositoryID: RepositoryTab.ID) {
		for kind in RepositorySidebarGroupKind.allCases {
			expandedGroups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
		}
	}
}

private struct RepositoryNavigationRows: View {
	@ObservedObject var workspace: WorkspaceViewModel
	let repositoryID: RepositoryTab.ID
	@Binding var expandedGroups: Set<RepositorySidebarGroup>

	var body: some View {
		sectionRow(.tree)
		sectionRow(.changes, badgeCount: workspace.changes.count)
		sectionRow(.history)

		navigationGroup(.branches, kind: .branches, selectsSection: false) {
			ForEach(workspace.branches) { branch in
				BranchSidebarRow(branch: branch)
					.tag(RepositorySidebarSelection.branch(repositoryID: repositoryID, id: branch.id))
					.help("Click to show \(branch.name) in History. Double-click to switch branches.")
			}
		}

		navigationGroup(.remotes, kind: .remotes, selectsSection: false) {
			ForEach(workspace.remotes) { remote in
				DisclosureGroup {
					ForEach(remote.branches) { branch in
						RemoteBranchSidebarRow(branch: branch)
							.tag(
								RepositorySidebarSelection.remoteBranch(
									repositoryID: repositoryID,
									id: branch.id
								)
							)
							.help("Show \(branch.fullName) in History")
					}
				} label: {
					SidebarChildRow(title: remote.name, systemImage: "icloud", accessory: nil)
				}
			}
		}

		tagNavigationGroup {
			ForEach(workspace.tags) { tag in
				TagSidebarRow(tag: tag)
					.tag(RepositorySidebarSelection.tag(repositoryID: repositoryID, id: tag.id))
					.help("Show \(tag.name) in History")
			}
		}

		navigationGroup(.stashes, kind: .stashes) {
			ForEach(workspace.stashes) { stash in
				SidebarChildRow(
					title: stash.subject,
					systemImage: "archivebox",
					accessory: stash.reference
				)
				.tag(RepositorySidebarSelection.stash(repositoryID: repositoryID, id: stash.id))
			}
		}
	}

	private func sectionRow(_ section: WorkspaceSection, badgeCount: Int? = nil) -> some View {
		SidebarSectionRow(section: section, badgeCount: badgeCount)
			.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
	}

	@ViewBuilder
	private func navigationGroup<Content: View>(
		_ section: WorkspaceSection,
		kind: RepositorySidebarGroupKind,
		selectsSection: Bool = true,
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		let group = RepositorySidebarGroup(
			repositoryID: repositoryID,
			kind: kind
		)
		let disclosureGroup = DisclosureGroup(
			isExpanded: Binding(
				get: { expandedGroups.contains(group) },
				set: { isExpanded in
					if isExpanded {
						expandedGroups.insert(group)
					} else {
						expandedGroups.remove(group)
					}
				}
			)
		) {
			content()
		} label: {
			SidebarSectionRow(section: section, badgeCount: nil)
		}

		if selectsSection {
			disclosureGroup
				.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
		} else {
			disclosureGroup
		}
	}

	private func tagNavigationGroup<Content: View>(
		@ViewBuilder content: @escaping () -> Content
	) -> some View {
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: .tags)
		return DisclosureGroup(
			isExpanded: Binding(
				get: { expandedGroups.contains(group) },
				set: { isExpanded in
					if isExpanded {
						expandedGroups.insert(group)
					} else {
						expandedGroups.remove(group)
					}
				}
			)
		) {
			content()
		} label: {
			SidebarGroupRow(title: "Tags", systemImage: "tag")
		}
	}

}

private struct RepositorySidebarGroup: Hashable {
	let repositoryID: RepositoryTab.ID
	let kind: RepositorySidebarGroupKind
}

private enum RepositorySidebarGroupKind: CaseIterable, Hashable {
	case branches
	case remotes
	case tags
	case stashes

	init?(section: WorkspaceSection) {
		switch section {
		case .branches:
			self = .branches
		case .remotes:
			self = .remotes
		case .stashes:
			self = .stashes
		case .changes, .history, .tree:
			return nil
		}
	}
}

private struct SidebarGroupRow: View {
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

private struct SidebarSectionRow: View {
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

private struct BranchSidebarRow: View {
	let branch: GitBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch",
			accessory: branch.isCurrent ? "Current" : nil
		)
	}
}

private struct RemoteBranchSidebarRow: View {
	let branch: GitRemoteBranch

	var body: some View {
		SidebarChildRow(
			title: branch.name,
			systemImage: "arrow.triangle.branch",
			accessory: nil
		)
	}
}

private struct TagSidebarRow: View {
	let tag: GitTag

	var body: some View {
		SidebarChildRow(title: tag.name, systemImage: "tag", accessory: nil)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct SidebarChildRow: View {
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
