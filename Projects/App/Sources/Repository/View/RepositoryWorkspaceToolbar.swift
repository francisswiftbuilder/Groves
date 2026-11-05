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
		ToolbarSpacer(.flexible, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			Button("New Branch", systemImage: "arrow.triangle.branch", action: onCreateBranch)
				.disabled(!referencesViewModel.canCreateBranch || isMutating || syncViewModel.isLoading)
				.help("Create a Branch from \(referencesViewModel.currentBranchName)")

			Button("Refresh", systemImage: "arrow.clockwise") {
				viewModel.didRequestRefresh()
			}
			.disabled(viewModel.isLoading || isMutating || syncViewModel.isLoading)
			.help("Refresh Repository")
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			RepositoryFetchToolbarControl(
				syncViewModel: syncViewModel, remotesViewModel: remotesViewModel
			)
			.disabled(isMutating)
			RepositoryPullToolbarControl(viewModel: syncViewModel)
				.disabled(isMutating)
			RepositoryPushMenu(viewModel: syncViewModel)
				.disabled(isMutating)
		}
	}

	private var isMutating: Bool {
		operationViewModel.isLoading || referencesViewModel.isLoading
	}
}
