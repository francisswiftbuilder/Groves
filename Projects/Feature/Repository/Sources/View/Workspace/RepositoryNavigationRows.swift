import DomainGitInterface
import SwiftUI

struct RepositoryNavigationRows: View {
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
