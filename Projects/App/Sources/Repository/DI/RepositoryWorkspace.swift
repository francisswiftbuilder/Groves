import CoreRepositoryDiff
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import FeatureRepositoryTree

@MainActor
final class RepositoryWorkspace {
	let viewModel: WorkspaceViewModel
	let changesViewModel: ChangesViewModel
	let changesDiffViewModel: ChangesDiffViewModel
	let commitViewModel: CommitViewModel
	let conflictViewModel: ConflictViewModel
	let historyViewModel: HistoryViewModel
	let operationViewModel: RepositoryOperationViewModel
	let referencesViewModel: RepositoryReferencesViewModel
	let syncViewModel: RepositorySyncViewModel
	let remotesViewModel: RemotesViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let changesDiffSearchViewModel: RepositorySearchViewModel
	let historyDiffSearchViewModel: RepositorySearchViewModel
	let stashesDiffSearchViewModel: RepositorySearchViewModel
	let commitActions: RepositoryCommitActions
	let focusedActions: () -> RepositoryFocusedActions

	init(
		viewModel: WorkspaceViewModel,
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
		focusedActions: @escaping () -> RepositoryFocusedActions
	) {
		self.viewModel = viewModel
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
	}
}
