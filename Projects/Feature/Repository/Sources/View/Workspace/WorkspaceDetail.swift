import DomainGitInterface
import SwiftUI

struct WorkspaceDetail: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	let changesViewModel: ChangesViewModel
	let historyViewModel: HistoryViewModel
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
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
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
				.navigationSubtitle(operationViewModel.currentBranchStatus)
			} else {
				switch viewModel.selectedSection ?? .changes {
				case .changes:
					ChangesView(
						viewModel: changesViewModel,
						diffPreferences: diffPreferences,
						repositoryName: viewModel.repositoryName,
						currentBranchStatus: operationViewModel.currentBranchStatus,
						repositoryURL: viewModel.repositoryURL,
						onDiffOptionsChanged: viewModel.didChangeDiffOptions
					)
				case .history, .branches:
					HistoryView(
						historyViewModel: historyViewModel,
						operationViewModel: operationViewModel,
						diffPreferences: diffPreferences,
						repositoryName: viewModel.repositoryName,
						currentBranchStatus: operationViewModel.currentBranchStatus,
						onDiffOptionsChanged: viewModel.didChangeDiffOptions
					)
				case .remotes:
					RemotesView(viewModel: operationViewModel)
				case .stashes:
					StashesView(
						changesViewModel: changesViewModel,
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
						viewModel: operationViewModel
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
