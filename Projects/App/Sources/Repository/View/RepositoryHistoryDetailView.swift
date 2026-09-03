import CoreRepositoryDiff
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import SwiftUI

struct RepositoryHistoryDetailView: View {
	let diffSearchViewModel: RepositorySearchViewModel
	let historyViewModel: HistoryViewModel
	@ObservedObject private var checkoutAvailability: HistoryCheckoutAvailability
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var referencesViewModel: RepositoryReferencesViewModel
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel
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
		_checkoutAvailability = ObservedObject(
			wrappedValue: historyViewModel.checkoutAvailability
		)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_referencesViewModel = ObservedObject(wrappedValue: referencesViewModel)
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
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
			isOperationLoading: operationViewModel.isLoading || syncViewModel.isLoading,
			canCheckoutCommit: referencesViewModel.canCheckoutCommit
				&& !checkoutAvailability.hasWorkingTreeChanges,
			remoteNames: Set(remotesViewModel.remotes.map(\.name)),
			commitActions: commitActions,
			onDiffOptionsChanged: onDiffOptionsChanged
		)
	}
}
