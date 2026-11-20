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
	let onManageRemotes: () -> Void
	let onManageStashes: () -> Void

	init(
		workspace: WorkspaceViewModel,
		changesViewModel: ChangesViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		remotesViewModel: RemotesViewModel,
		stashesViewModel: StashesViewModel,
		repositoryID: RepositoryTab.ID,
		onCreateBranch: @escaping () -> Void,
		onManageRemotes: @escaping () -> Void,
		onManageStashes: @escaping () -> Void
	) {
		self.workspace = workspace
		self.changesViewModel = changesViewModel
		self.referencesViewModel = referencesViewModel
		self.remotesViewModel = remotesViewModel
		self.stashesViewModel = stashesViewModel
		self.repositoryID = repositoryID
		self.onCreateBranch = onCreateBranch
		self.onManageRemotes = onManageRemotes
		self.onManageStashes = onManageStashes
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

		Section(isExpanded: expansion(for: .remotes)) {
			ForEach(remotesViewModel.remoteBranches) { branch in
				RemoteBranchSidebarRow(branch: branch, showsRemoteName: remotesViewModel.remotes.count > 1)
					.tag(RepositorySidebarSelection.remoteBranch(repositoryID: repositoryID, id: branch.id))
					.help(remoteBranchHelp(branch))
			}
		} header: {
			HStack {
				Text("Remotes")
				if remotesViewModel.remotes.contains(where: { $0.fetchError != nil }) {
					Image(systemName: "exclamationmark.circle")
						.foregroundStyle(.secondary)
						.accessibilityLabel("Some remotes could not be refreshed")
				}
			}
			.help(
				remotesViewModel.remotes.map { "\($0.name) · \(fetchStatus($0))" }.joined(separator: "\n")
			)
			.contextMenu {
				Button("Manage Remotes…", systemImage: "network", action: onManageRemotes)
				Button("Add Remote…", systemImage: "plus") {
					remotesViewModel.didPresentAddRemote()
				}
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

		Section(isExpanded: expansion(for: .stashes)) {
			ForEach(stashesViewModel.stashes) { stash in
				SidebarChildRow(title: stash.subject, systemImage: "archivebox", accessory: nil)
					.tag(RepositorySidebarSelection.stash(repositoryID: repositoryID, id: stash.id))
					.help("\(stash.reference) · \(stash.subject)")
			}
		} header: {
			Text("Stashes").contextMenu {
				Button("Manage Stashes…", systemImage: "archivebox", action: onManageStashes)
			}
		}
	}

	private func remoteBranchHelp(_ branch: GitRemoteBranch) -> String {
		guard branch.remoteReference != nil else {
			return "\(branch.fullName) · Server branch is unverified. Review the remote’s fetch mappings."
		}
		guard let remote = remotesViewModel.remotes.first(where: { $0.name == branch.remoteName })
		else { return branch.remoteDisplayName }
		return "\(branch.remoteDisplayName) · \(fetchStatus(remote))"
	}

	private func fetchStatus(_ remote: GitRemote) -> String {
		let timestamp =
			remote.lastFetchedAt.map {
				"Last fetched \($0.formatted(date: .abbreviated, time: .shortened))"
			}
			?? "No confirmed fetch in this session"
		if remote.fetchError != nil { return "Fetch failed. \(timestamp)." }
		return timestamp
	}

	private func sectionRow(
		_ section: WorkspaceSection, badgeCount: Int? = nil
	) -> some View {
		SidebarSectionRow(section: section, badgeCount: badgeCount)
			.tag(RepositorySidebarSelection.section(repositoryID: repositoryID, section: section))
	}

	private func expansion(for kind: RepositorySidebarGroupKind) -> Binding<Bool> {
		let group = RepositorySidebarGroup(repositoryID: repositoryID, kind: kind)
		return Binding(
			get: { workspace.expandedSidebarGroups.contains(group) },
			set: { workspace.setSidebarGroup(group, isExpanded: $0) })
	}
}
