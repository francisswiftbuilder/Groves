@MainActor
final class RepositoryWorkspace {
	let viewModel: WorkspaceViewModel
	let changesViewModel: ChangesViewModel
	let historyViewModel: HistoryViewModel
	let operationViewModel: RepositoryOperationViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences

	init(
		viewModel: WorkspaceViewModel,
		changesViewModel: ChangesViewModel,
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		stashesViewModel: StashesViewModel,
		treeViewModel: RepositoryTreeViewModel,
		diffPreferences: WorkspaceDiffPreferences
	) {
		self.viewModel = viewModel
		self.changesViewModel = changesViewModel
		self.historyViewModel = historyViewModel
		self.operationViewModel = operationViewModel
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
	}
}
