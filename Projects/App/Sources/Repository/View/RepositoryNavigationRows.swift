import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import SwiftUI

struct RepositoryNavigationRows: View {
	let workspace: WorkspaceViewModel
	private let changesViewModel: ChangesViewModel
	private let referencesViewModel: RepositoryReferencesViewModel
	private let remotesViewModel: RemotesViewModel
	private let stashesViewModel: StashesViewModel
	let repositoryID: RepositoryTab.ID
	let onCreateBranch: () -> Void

	init(
		workspace: WorkspaceViewModel,
		changesViewModel: ChangesViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		remotesViewModel: RemotesViewModel,
		stashesViewModel: StashesViewModel,
		repositoryID: RepositoryTab.ID,
		onCreateBranch: @escaping () -> Void
	) {
		self.workspace = workspace
		self.changesViewModel = changesViewModel
		self.referencesViewModel = referencesViewModel
		self.remotesViewModel = remotesViewModel
		self.stashesViewModel = stashesViewModel
		self.repositoryID = repositoryID
		self.onCreateBranch = onCreateBranch
	}

	var body: some View {
		Section("Repository") {
			sectionRow(.changes, badgeCount: changesViewModel.changes.count)
			sectionRow(.history)
			sectionRow(.tree)
		}

		Section(isExpanded: expansion(for: .branches)) {
			ForEach(referencesViewModel.branches) { branch in
				BranchSidebarRow(branch: branch)
					.tag(RepositorySidebarSelection.branch(repositoryID: repositoryID, id: branch.id))
			}
		} header: {
			Text("Branches").contextMenu {
				Button("New Branch…", systemImage: "plus", action: onCreateBranch)
			}
		}

		Section("Remotes", isExpanded: expansion(for: .remotes)) {
			sectionRow(.remotes, title: "All Remotes")
			ForEach(remotesViewModel.remotes) { remote in
				DisclosureGroup {
					ForEach(remote.branches) { branch in
						RemoteBranchSidebarRow(branch: branch)
							.tag(
								RepositorySidebarSelection.remoteBranch(repositoryID: repositoryID, id: branch.id)
							)
							.help(branch.fullName)
					}
				} label: {
					SidebarChildRow(title: remote.name, systemImage: "network", accessory: nil)
				}
				.tag(RepositorySidebarSelection.remote(repositoryID: repositoryID, id: remote.id))
			}
		}

		if !referencesViewModel.tags.isEmpty {
			Section("Tags", isExpanded: expansion(for: .tags)) {
				ForEach(referencesViewModel.tags) { tag in
					TagSidebarRow(tag: tag)
						.tag(RepositorySidebarSelection.tag(repositoryID: repositoryID, id: tag.id))
						.help(tag.name)
				}
			}
		}

		Section("Stashes", isExpanded: expansion(for: .stashes)) {
			sectionRow(.stashes, title: "All Stashes", badgeCount: stashesViewModel.stashes.count)
			ForEach(stashesViewModel.stashes) { stash in
				SidebarChildRow(title: stash.subject, systemImage: "archivebox", accessory: nil)
					.tag(RepositorySidebarSelection.stash(repositoryID: repositoryID, id: stash.id))
					.help("\(stash.reference) · \(stash.subject)")
			}
		}
	}

	private func sectionRow(
		_ section: WorkspaceSection, title: String? = nil, badgeCount: Int? = nil
	) -> some View {
		SidebarSectionRow(section: section, title: title, badgeCount: badgeCount)
			.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
	}

	private func expansion(for kind: RepositorySidebarGroupKind) -> Binding<Bool> {
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: kind)
		return Binding(
			get: { workspace.expandedSidebarGroups.contains(group) },
			set: { workspace.setSidebarGroup(group, isExpanded: $0) })
	}
}
