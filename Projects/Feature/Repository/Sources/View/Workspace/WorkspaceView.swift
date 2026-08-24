import SwiftUI

struct WorkspaceView: View {
	@Environment(\.scenePhase) private var scenePhase
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	let repositoryID: RepositoryTab.ID

	var body: some View {
		NavigationSplitView {
			RepositorySidebar(
				viewModel: viewModel,
				windowViewModel: windowViewModel,
				repositoryID: repositoryID
			)
			.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			WorkspaceDetail(viewModel: viewModel)
		}
		.alert(
			"Git Error",
			isPresented: Binding(
				get: { viewModel.alertMessage != nil },
				set: { isPresented in
					if !isPresented {
						viewModel.alertMessage = nil
					}
				}
			),
			actions: {
				Button("OK") {
					viewModel.alertMessage = nil
				}
			},
			message: {
				Text(viewModel.alertMessage ?? "")
			}
		)
		.alert("New Branch", isPresented: newBranchPresentation) {
			TextField("Branch name", text: $viewModel.newBranchName)
			Button("Cancel", role: .cancel) {
				viewModel.didDismissNewBranch()
			}
			Button("Create") {
				viewModel.didRequestCreateBranch()
			}
			.disabled(
				viewModel.newBranchName
					.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			)
		} message: {
			Text("Create and switch to a new branch from the current branch.")
		}
		.alert("New Tag", isPresented: newTagPresentation) {
			TextField("Tag name", text: $viewModel.newTagName)
			TextField("Message (optional)", text: $viewModel.newTagMessage)
			Button("Cancel", role: .cancel) {
				viewModel.didDismissNewTag()
			}
			Button("Create") {
				viewModel.didRequestCreateTag()
			}
			.disabled(
				viewModel.newTagName
					.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			)
		} message: {
			Text("Create a tag at commit \(viewModel.pendingTagCommit?.shortHash ?? "").")
		}
		.confirmationDialog(
			viewModel.deleteTagConfirmationTitle,
			isPresented: deleteTagPresentation,
			presenting: viewModel.pendingTagDeletion
		) { tag in
			Button("Delete Tag", role: .destructive) {
				if case .tag(_, let id) = windowViewModel.sidebarSelection,
					id == tag.id
				{
					windowViewModel.selectSidebarItem(nil)
				}
				viewModel.didConfirmTagDeletion(tag)
			}
			Button("Cancel", role: .cancel) {
				viewModel.didDismissTagDeletion()
			}
		} message: { tag in
			Text("The local tag “\(tag.name)” will be deleted. This does not delete a remote tag.")
		}
		.confirmationDialog(
			viewModel.forcePushConfirmationTitle,
			isPresented: forcePushPresentation
		) {
			Button("Force Push with Lease", role: .destructive) {
				viewModel.didConfirmForcePush()
			}
			Button("Cancel", role: .cancel) {
				viewModel.didDismissForcePushConfirmation()
			}
		} message: {
			Text(viewModel.forcePushConfirmationMessage)
		}
		.task(id: workingTreeMonitorID) {
			guard scenePhase == .active else { return }
			await viewModel.monitorRepositoryChanges()
		}
	}

	private var newBranchPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.isPresentingNewBranch },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewBranch()
				}
			}
		)
	}

	private var newTagPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingTagCommit != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewTag()
				}
			}
		)
	}

	private var deleteTagPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingTagDeletion != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissTagDeletion()
				}
			}
		)
	}

	private var forcePushPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.isPresentingForcePushConfirmation },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissForcePushConfirmation()
				}
			}
		)
	}

	private var workingTreeMonitorID: WorkingTreeMonitorID {
		WorkingTreeMonitorID(
			repositoryURL: viewModel.repositoryURL,
			scenePhase: scenePhase
		)
	}
}
