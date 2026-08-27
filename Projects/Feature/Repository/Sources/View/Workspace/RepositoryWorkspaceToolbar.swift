import SwiftUI

struct RepositoryWorkspaceToolbar: ToolbarContent {
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	let onCreateBranch: () -> Void

	init(
		viewModel: WorkspaceViewModel,
		operationViewModel: RepositoryOperationViewModel,
		onCreateBranch: @escaping () -> Void
	) {
		self.viewModel = viewModel
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
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
				operationViewModel.isLoading
					|| operationViewModel.currentBranch == nil
						&& !operationViewModel.operationState.isDetached
			)
			.help("Create a Branch from \(operationViewModel.currentBranchName)")
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				viewModel.didRequestRefresh()
			} label: {
				Label("Refresh", systemImage: "arrow.clockwise")
			}
			.disabled(viewModel.isLoading || operationViewModel.isLoading)
			.help("Refresh Repository")

			if operationViewModel.isLoading {
				ControlGroup {
					ProgressView()
						.controlSize(.small)
						.accessibilityLabel("Git operation in progress")

					Button("Cancel", systemImage: "xmark.circle") {
						operationViewModel.didRequestCancelOperation()
					}
					.help("Cancel Git Operation")
				}
			} else {
				Menu {
					Button("Fetch All Remotes", systemImage: "arrow.triangle.2.circlepath") {
						operationViewModel.didRequestFetchAll()
					}

					if !operationViewModel.remotes.isEmpty {
						Divider()
						ForEach(operationViewModel.remotes) { remote in
							Button(remote.name, systemImage: "icloud.and.arrow.down") {
								operationViewModel.didRequestFetch(remoteName: remote.name)
							}
						}
					}
				} label: {
					Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
				}
				.accessibilityLabel("Fetch")
				.disabled(operationViewModel.remotes.isEmpty)
				.help("Fetch Remote References")
			}
		}

		ToolbarSpacer(.fixed, placement: .primaryAction)

		ToolbarItemGroup(placement: .primaryAction) {
			if !operationViewModel.isLoading {
				Button {
					operationViewModel.didRequestPull()
				} label: {
					Label("Pull", systemImage: "arrow.down")
				}
				.help("Pull Current Branch")

				RepositoryPushMenu(viewModel: operationViewModel)
			}
		}
	}
}
