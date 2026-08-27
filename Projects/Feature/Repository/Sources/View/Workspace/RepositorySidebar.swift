import DomainGitInterface
import SwiftUI

struct RepositorySidebar: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	@ObservedObject private var changesViewModel: ChangesViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var stashesViewModel: StashesViewModel
	let repositoryID: RepositoryTab.ID

	init(
		viewModel: WorkspaceViewModel,
		windowViewModel: RepositoryWindowViewModel,
		changesViewModel: ChangesViewModel,
		operationViewModel: RepositoryOperationViewModel,
		stashesViewModel: StashesViewModel,
		repositoryID: RepositoryTab.ID
	) {
		self.viewModel = viewModel
		self.windowViewModel = windowViewModel
		_changesViewModel = ObservedObject(wrappedValue: changesViewModel)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_stashesViewModel = ObservedObject(wrappedValue: stashesViewModel)
		self.repositoryID = repositoryID
	}

	var body: some View {
		List(selection: selectedItemBinding) {
			RepositoryNavigationRows(
				workspace: viewModel,
				changesViewModel: changesViewModel,
				operationViewModel: operationViewModel,
				stashesViewModel: stashesViewModel,
				repositoryID: repositoryID,
				onCreateBranch: { operationViewModel.didPresentNewBranch() }
			)
		}
		.listStyle(.sidebar)
		.contextMenu(forSelectionType: RepositorySidebarSelection.self) { selections in
			sidebarContextMenu(for: selections)
		} primaryAction: { selections in
			performPrimaryAction(for: selections)
		}
		.onAppear {
			viewModel.didPrepareSidebar(repositoryID: repositoryID)
		}
	}

	private var selectedItemBinding: Binding<RepositorySidebarSelection?> {
		Binding(
			get: { windowViewModel.sidebarSelection },
			set: { selection in
				Task {
					await windowViewModel.didSelectSidebarItem(selection)
				}
			}
		)
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
				if let branch = operationViewModel.branches.first(where: { $0.id == id }) {
					Button("Switch to \(branch.name)", systemImage: "arrow.triangle.branch") {
						selectBranch(branch)
						operationViewModel.didRequestSwitchBranch()
					}
					.disabled(branch.isCurrent)

					if let currentBranch = operationViewModel.currentBranch, !branch.isCurrent {
						Button(
							"Merge \(branch.name) into \(currentBranch.name)",
							systemImage: "arrow.triangle.merge"
						) {
							operationViewModel.didRequestMergeBranch(branch)
						}
						.disabled(!operationViewModel.canMergeBranch(branch))

						Button(
							"Rebase \(currentBranch.name) onto \(branch.name)",
							systemImage: "arrow.triangle.2.circlepath"
						) {
							operationViewModel.didRequestRebase(onto: branch)
						}
						.disabled(!operationViewModel.canRebaseOnto(branch))
					}

					Button("Rename…", systemImage: "pencil") {
						operationViewModel.didPresentBranchRename(branch)
					}
					.disabled(!operationViewModel.operationState.isIdle || operationViewModel.isLoading)

					Divider()

					Button("Delete Branch", systemImage: "trash", role: .destructive) {
						operationViewModel.didPresentBranchDeletion(branch)
					}
					.disabled(branch.isCurrent)
				}
			case .stash(_, let id):
				if let stash = stashesViewModel.stashes.first(where: { $0.id == id }) {
					Button("Apply Stash", systemImage: "arrow.down.doc") {
						selectStash(stash)
						stashesViewModel.didRequestApplyStash()
					}

					Button("Pop Stash", systemImage: "arrow.up.doc") {
						selectStash(stash)
						stashesViewModel.didRequestPopStash()
					}

					Divider()

					Button("Delete Stash", systemImage: "trash", role: .destructive) {
						stashesViewModel.didPresentStashDrop(stash)
					}
				}
			case .remoteBranch(_, let id):
				if let remoteBranch = operationViewModel.remoteBranches.first(where: { $0.id == id }) {
					if let localBranch = localBranch(tracking: remoteBranch) {
						Button(
							"Switch to \(localBranch.name)",
							systemImage: "arrow.triangle.branch"
						) {
							switchToRemoteBranch(remoteBranch)
						}
						.disabled(localBranch.isCurrent)
					} else {
						Button("Create Local Branch", systemImage: "arrow.down.to.line") {
							switchToRemoteBranch(remoteBranch)
						}
					}

					Divider()
					Button("Delete Remote Branch…", systemImage: "trash", role: .destructive) {
						operationViewModel.didPresentRemoteBranchDeletion(remoteBranch)
					}
				}
			case .tag(_, let id):
				if let tag = operationViewModel.tags.first(where: { $0.id == id }) {
					Button("Delete Tag", systemImage: "trash", role: .destructive) {
						operationViewModel.didPresentTagDeletion(tag)
					}
				}
			case .section, .remote:
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
			selection.repositoryID == repositoryID
		else { return }

		switch selection {
		case .branch(_, let id):
			guard let branch = operationViewModel.branches.first(where: { $0.id == id }) else {
				return
			}
			selectBranch(branch)
			operationViewModel.didRequestSwitchBranch()
		case .remoteBranch(_, let id):
			guard
				let remoteBranch = operationViewModel.remoteBranches.first(where: { $0.id == id })
			else { return }
			switchToRemoteBranch(remoteBranch)
		case .section, .remote, .tag, .stash:
			return
		}
	}

	private func switchToRemoteBranch(_ remoteBranch: GitRemoteBranch) {
		if let localBranch = localBranch(tracking: remoteBranch) {
			selectBranch(localBranch)
			operationViewModel.didRequestSwitchBranch()
		} else {
			operationViewModel.didRequestCreateLocalBranch(from: remoteBranch)
		}
	}

	private func localBranch(tracking remoteBranch: GitRemoteBranch) -> GitBranch? {
		operationViewModel.branches.first { $0.upstream == remoteBranch.fullName }
			?? operationViewModel.branches.first { $0.name == remoteBranch.name }
	}

	private func selectBranch(_ branch: GitBranch) {
		windowViewModel.selectSidebarItem(
			.branch(repositoryID: repositoryID, id: branch.id)
		)
		operationViewModel.selectedBranchID = branch.id
	}

	private func selectStash(_ stash: GitStash) {
		windowViewModel.selectSidebarItem(
			.stash(repositoryID: repositoryID, id: stash.id)
		)
		stashesViewModel.selectedStashID = stash.id
	}
}
