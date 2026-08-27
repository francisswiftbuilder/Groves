import FeatureRepositoryOperations
import SwiftUI

struct RepositoryWorkspaceToolbar: ToolbarContent {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var referencesViewModel: RepositoryReferencesViewModel
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel
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
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_referencesViewModel = ObservedObject(wrappedValue: referencesViewModel)
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
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

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				viewModel.didRequestRefresh()
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.disabled(viewModel.isLoading || operationViewModel.isLoading || syncViewModel.isLoading)
			.help("Refresh Repository")

			if syncViewModel.isLoading {
				ControlGroup {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel("Git operation in progress")

					Button("Cancel", systemImage: "xmark.circle") {
						syncViewModel.didRequestCancelOperation()
					}
					.help("Cancel Git Operation")
				}
			} else {
				Menu {
					Button("Fetch All Remotes", systemImage: "arrow.triangle.2.circlepath") {
						syncViewModel.didRequestFetchAll()
					}

					if !remotesViewModel.remotes.isEmpty {
						Divider()
						ForEach(remotesViewModel.remotes) { remote in
							Button(remote.name, systemImage: "icloud.and.arrow.down") {
								syncViewModel.didRequestFetch(remoteName: remote.name)
							}
						}
					}
				} label: {
					Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
				}
				.accessibilityLabel("Fetch")
				.disabled(remotesViewModel.remotes.isEmpty)
				.help("Fetch Remote References")
			}
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			if !syncViewModel.isLoading {
				Button {
					syncViewModel.didRequestPull()
				} label: {
					Label("Pull", systemImage: "arrow.down")
				}
				.help("Pull Current Branch")

				RepositoryPushMenu(viewModel: syncViewModel)
			}
		}
	}
}
