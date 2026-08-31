import CoreRepositoryDiff
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import FeatureRepositoryTree
import SwiftUI

struct WorkspaceView: View {
	let viewModel: WorkspaceViewModel
	let windowViewModel: RepositoryWindowViewModel
	let historyViewModel: HistoryViewModel
	let operationViewModel: RepositoryOperationViewModel
	let referencesViewModel: RepositoryReferencesViewModel
	let syncViewModel: RepositorySyncViewModel
	let remotesViewModel: RemotesViewModel
	let changesViewModel: ChangesViewModel
	let changesDiffViewModel: ChangesDiffViewModel
	let commitViewModel: CommitViewModel
	let conflictViewModel: ConflictViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let changesDiffSearchViewModel: RepositorySearchViewModel
	let historyDiffSearchViewModel: RepositorySearchViewModel
	let stashesDiffSearchViewModel: RepositorySearchViewModel
	let commitActions: RepositoryCommitActions
	let focusedActions: () -> RepositoryFocusedActions
	let repositoryID: RepositoryTab.ID

	init(
		viewModel: WorkspaceViewModel,
		windowViewModel: RepositoryWindowViewModel,
		changesViewModel: ChangesViewModel,
		changesDiffViewModel: ChangesDiffViewModel,
		commitViewModel: CommitViewModel,
		conflictViewModel: ConflictViewModel,
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel,
		stashesViewModel: StashesViewModel,
		treeViewModel: RepositoryTreeViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		changesDiffSearchViewModel: RepositorySearchViewModel,
		historyDiffSearchViewModel: RepositorySearchViewModel,
		stashesDiffSearchViewModel: RepositorySearchViewModel,
		commitActions: RepositoryCommitActions,
		focusedActions: @escaping () -> RepositoryFocusedActions,
		repositoryID: RepositoryTab.ID
	) {
		self.viewModel = viewModel
		self.windowViewModel = windowViewModel
		self.changesViewModel = changesViewModel
		self.changesDiffViewModel = changesDiffViewModel
		self.commitViewModel = commitViewModel
		self.conflictViewModel = conflictViewModel
		self.historyViewModel = historyViewModel
		self.operationViewModel = operationViewModel
		self.referencesViewModel = referencesViewModel
		self.syncViewModel = syncViewModel
		self.remotesViewModel = remotesViewModel
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
		self.changesDiffSearchViewModel = changesDiffSearchViewModel
		self.historyDiffSearchViewModel = historyDiffSearchViewModel
		self.stashesDiffSearchViewModel = stashesDiffSearchViewModel
		self.commitActions = commitActions
		self.focusedActions = focusedActions
		self.repositoryID = repositoryID
	}

	var body: some View {
		RepositoryReferencesPresentationHost(
			viewModel: referencesViewModel,
			onConfirmDeleteTag: clearDeletedSidebarSelection
		) {
			RepositorySyncPresentationHost(viewModel: syncViewModel) {
				RepositoryRemotePresentationHost(viewModel: remotesViewModel) {
					RepositoryOperationPresentationHost(viewModel: operationViewModel) {
						NavigationSplitView {
							RepositorySidebar(
								viewModel: viewModel,
								windowViewModel: windowViewModel,
								changesViewModel: changesViewModel,
								operationViewModel: operationViewModel,
								referencesViewModel: referencesViewModel,
								remotesViewModel: remotesViewModel,
								stashesViewModel: stashesViewModel,
								repositoryID: repositoryID
							)
							.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
						} detail: {
							WorkspaceDetail(
								viewModel: viewModel,
								changesViewModel: changesViewModel,
								changesDiffViewModel: changesDiffViewModel,
								commitViewModel: commitViewModel,
								conflictViewModel: conflictViewModel,
								historyViewModel: historyViewModel,
								operationViewModel: operationViewModel,
								referencesViewModel: referencesViewModel,
								syncViewModel: syncViewModel,
								remotesViewModel: remotesViewModel,
								stashesViewModel: stashesViewModel,
								treeViewModel: treeViewModel,
								diffPreferences: diffPreferences,
								changesDiffSearchViewModel: changesDiffSearchViewModel,
								historyDiffSearchViewModel: historyDiffSearchViewModel,
								stashesDiffSearchViewModel: stashesDiffSearchViewModel,
								commitActions: commitActions
							)
						}
					}
				}
			}
		}
		.modifier(RepositoryMonitoringModifier(viewModel: viewModel))
		.modifier(
			RepositoryFocusedActionsModifier(
				historyViewModel: historyViewModel,
				operationViewModel: operationViewModel,
				referencesViewModel: referencesViewModel,
				remotesViewModel: remotesViewModel,
				actions: focusedActions
			)
		)
	}

	private func clearDeletedSidebarSelection(for tag: GitTag) {
		guard case .tag(let repositoryID, let id) = windowViewModel.sidebarSelection else { return }
		guard tag.id == id, repositoryID == self.repositoryID else { return }
		windowViewModel.selectSidebarItem(nil)
	}

}
