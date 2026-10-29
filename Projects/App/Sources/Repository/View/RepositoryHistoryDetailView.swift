import CoreRepositoryDiff
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import SwiftUI

struct RepositoryHistoryDetailView: View {
	let diffSearchViewModel: RepositorySearchViewModel
	let historyViewModel: HistoryViewModel
	private let operationViewModel: RepositoryOperationViewModel
	private let referencesViewModel: RepositoryReferencesViewModel
	private let syncViewModel: RepositorySyncViewModel
	private let remotesViewModel: RemotesViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let repositoryName: String
	let commitActions: RepositoryCommitActions
	let onDiffOptionsChanged: () -> Void

	init(
		diffSearchViewModel: RepositorySearchViewModel,
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		repositoryName: String,
		commitActions: RepositoryCommitActions,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		self.diffSearchViewModel = diffSearchViewModel
		self.historyViewModel = historyViewModel
		self.operationViewModel = operationViewModel
		self.referencesViewModel = referencesViewModel
		self.syncViewModel = syncViewModel
		self.remotesViewModel = remotesViewModel
		self.diffPreferences = diffPreferences
		self.repositoryName = repositoryName
		self.commitActions = commitActions
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	var body: some View {
		HistoryView(
			diffSearchViewModel: diffSearchViewModel,
			historyViewModel: historyViewModel,
			diffPreferences: diffPreferences,
			repositoryName: repositoryName,
			currentBranchStatus: referencesViewModel.currentBranchStatus,
			operationState: operationViewModel.operationState,
			isOperationLoading: operationViewModel.isLoading || syncViewModel.isLoading
				|| referencesViewModel.isLoading,
			canCheckoutCommit: referencesViewModel.canCheckoutCommit
				&& !historyViewModel.hasWorkingTreeChanges
				&& !operationViewModel.isLoading && !syncViewModel.isLoading,
			remoteNames: Set(remotesViewModel.remotes.map(\.name)),
			commitActions: commitActions,
			onDiffOptionsChanged: onDiffOptionsChanged
		)
	}
}
