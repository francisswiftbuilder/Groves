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

	private var workingTreeMonitorID: WorkingTreeMonitorID {
		WorkingTreeMonitorID(
			repositoryURL: viewModel.repositoryURL,
			scenePhase: scenePhase
		)
	}
}
