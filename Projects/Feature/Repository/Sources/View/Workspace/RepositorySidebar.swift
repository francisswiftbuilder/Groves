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
