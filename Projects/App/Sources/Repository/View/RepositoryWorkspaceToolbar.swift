import FeatureRepositoryOperations
import SwiftUI

struct RepositoryWorkspaceToolbar: ToolbarContent {
	let viewModel: WorkspaceViewModel
	private let operationViewModel: RepositoryOperationViewModel
	private let referencesViewModel: RepositoryReferencesViewModel
	private let syncViewModel: RepositorySyncViewModel
	private let remotesViewModel: RemotesViewModel
	let onCreateBranch: () -> Void

	init(
		viewModel: WorkspaceViewModel,
		operationViewModel: RepositoryOperationViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel,
		onCreateBranch: @escaping () -> Void
	) {
		self.viewModel = viewModel
		self.operationViewModel = operationViewModel
		self.referencesViewModel = referencesViewModel
		self.syncViewModel = syncViewModel
		self.remotesViewModel = remotesViewModel
		self.onCreateBranch = onCreateBranch
	}

	var body: some ToolbarContent {
		ToolbarItem(placement: .primaryAction) {
			Button {
				onCreateBranch()
			} label: {
				Label("New Branch", systemImage: "arrow.triangle.branch")
			}
			.disabled(
				operationViewModel.isLoading || referencesViewModel.isLoading || syncViewModel.isLoading
					|| referencesViewModel.currentBranch == nil
						&& !referencesViewModel.operationState.isDetached
			)
			.help("Create a Branch from \(referencesViewModel.currentBranchName)")
		}

		if let activity = syncViewModel.presentedActivity {
			ToolbarItem(placement: .primaryAction) {
				RepositorySyncProgressIndicator(activity: activity)
			}
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				viewModel.didRequestRefresh()
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.disabled(viewModel.isLoading || operationViewModel.isLoading || syncViewModel.isLoading)
			.help("Refresh Repository")

			RepositoryFetchToolbarControl(
				syncViewModel: syncViewModel,
				remotesViewModel: remotesViewModel
			)
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			RepositoryPullToolbarControl(viewModel: syncViewModel)
			RepositoryPushMenu(viewModel: syncViewModel)
		}
	}
}
