import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import SwiftUI

struct WorkspaceDetail: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var referencesViewModel: RepositoryReferencesViewModel
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel
	let changesViewModel: ChangesViewModel
	let changesDiffViewModel: ChangesDiffViewModel
	let commitViewModel: CommitViewModel
	let conflictViewModel: ConflictViewModel
	let historyViewModel: HistoryViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let commitActions: RepositoryCommitActions

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
		commitActions: RepositoryCommitActions
	) {
		self.viewModel = viewModel
		self.changesViewModel = changesViewModel
		self.changesDiffViewModel = changesDiffViewModel
		self.commitViewModel = commitViewModel
		self.conflictViewModel = conflictViewModel
		self.historyViewModel = historyViewModel
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_referencesViewModel = ObservedObject(wrappedValue: referencesViewModel)
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
		self.commitActions = commitActions
	}

	var body: some View {
		Group {
			if viewModel.repositoryURL == nil {
				EmptyStateView(
					title: "Open a Git Repository",
					message: "Choose a local repository to inspect changes, history, tags, and files.",
					systemImage: "externaldrive.badge.plus"
				)
			} else if viewModel.isLoadingContent {
				LoadingStateView(
					title: "Loading Repository",
					message: "Fetching changes, history, branches, tags, and files."
				)
				.navigationTitle(viewModel.repositoryName)
				.navigationSubtitle(referencesViewModel.currentBranchStatus)
			} else {
				switch viewModel.selectedSection ?? .changes {
				case .changes:
					ChangesView(
						viewModel: changesViewModel,
						diffViewModel: changesDiffViewModel,
						commitViewModel: commitViewModel,
						conflictViewModel: conflictViewModel,
						diffPreferences: diffPreferences,
						repositoryName: viewModel.repositoryName,
						currentBranchStatus: referencesViewModel.currentBranchStatus,
						repositoryURL: viewModel.repositoryURL,
						onDiffOptionsChanged: viewModel.didChangeDiffOptions
					)
				case .history, .branches:
					HistoryView(
						historyViewModel: historyViewModel,
						diffPreferences: diffPreferences,
						repositoryName: viewModel.repositoryName,
						currentBranchStatus: referencesViewModel.currentBranchStatus,
						operationState: operationViewModel.operationState,
						isOperationLoading: operationViewModel.isLoading || syncViewModel.isLoading,
						canCheckoutCommit: referencesViewModel.canCheckoutCommit,
						remoteNames: Set(remotesViewModel.remotes.map(\.name)),
						commitActions: commitActions,
						onDiffOptionsChanged: viewModel.didChangeDiffOptions
					)
				case .remotes:
					RemotesView(
						viewModel: remotesViewModel,
						syncViewModel: syncViewModel
					)
				case .stashes:
					StashesView(
						stashesViewModel: stashesViewModel,
						diffPreferences: diffPreferences,
						onDiffOptionsChanged: viewModel.didChangeDiffOptions
					)
				case .tree:
					RepositoryTreeView(viewModel: treeViewModel)
				}
			}
		}
		.safeAreaInset(edge: .top) {
			VStack(spacing: 0) {
				if let message = viewModel.alertMessage {
					RepositoryErrorBanner(message: message) {
						viewModel.alertMessage = nil
					}
				}
				if operationViewModel.operationState.isDetached {
					RepositoryDetachedHeadBanner(
						viewModel: referencesViewModel
					)
				}
				if operationViewModel.operationState.operation != nil
					|| operationViewModel.operationState.hasConflicts
				{
					RepositoryOperationBanner(
						viewModel: operationViewModel
					)
				}
			}
		}
	}
}
