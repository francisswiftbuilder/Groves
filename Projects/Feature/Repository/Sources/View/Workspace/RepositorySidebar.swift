import DomainGitInterface
import SwiftUI

struct RepositorySidebar: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	let repositoryID: RepositoryTab.ID

	var body: some View {
		List(selection: selectedItemBinding) {
			RepositoryNavigationRows(
				workspace: viewModel,
				repositoryID: repositoryID,
				onCreateBranch: viewModel.didPresentNewBranch
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
			case .remoteBranch(_, let id):
				if let remoteBranch = viewModel.remoteBranches.first(where: { $0.id == id }) {
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
				}
			case .section, .remote, .tag:
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
			guard let branch = viewModel.branches.first(where: { $0.id == id }) else { return }
			selectBranch(branch)
			viewModel.didRequestSwitchBranch()
		case .remoteBranch(_, let id):
			guard
				let remoteBranch = viewModel.remoteBranches.first(where: { $0.id == id })
			else { return }
			switchToRemoteBranch(remoteBranch)
		case .section, .remote, .tag, .stash:
			return
		}
	}

	private func switchToRemoteBranch(_ remoteBranch: GitRemoteBranch) {
		if let localBranch = localBranch(tracking: remoteBranch) {
			selectBranch(localBranch)
			viewModel.didRequestSwitchBranch()
		} else {
			viewModel.didRequestCreateLocalBranch(from: remoteBranch)
		}
	}

	private func localBranch(tracking remoteBranch: GitRemoteBranch) -> GitBranch? {
		viewModel.branches.first { $0.upstream == remoteBranch.fullName }
			?? viewModel.branches.first { $0.name == remoteBranch.name }
	}

	private func selectBranch(_ branch: GitBranch) {
		windowViewModel.selectSidebarItem(
			.branch(repositoryID: repositoryID, id: branch.id)
		)
		viewModel.selectedBranchID = branch.id
	}

	private func selectStash(_ stash: GitStash) {
		windowViewModel.selectSidebarItem(
			.stash(repositoryID: repositoryID, id: stash.id)
		)
		viewModel.selectedStashID = stash.id
	}
}
