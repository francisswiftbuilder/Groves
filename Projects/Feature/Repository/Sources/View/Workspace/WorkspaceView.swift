import SwiftUI

struct WorkspaceView: View {
	@Environment(\.scenePhase) private var scenePhase
	@ObservedObject var viewModel: WorkspaceViewModel
	let repositories: [RepositoryTab]
	let selectedRepositoryID: RepositoryTab.ID?
	@Binding var sidebarSelection: RepositorySidebarSelection?
	let onSelectRepository: (RepositoryTab.ID) -> Void
	let onCloseRepository: (RepositoryTab.ID) -> Void
	let onAddRepository: () -> Void

	var body: some View {
		NavigationSplitView {
			RepositorySidebar(
				viewModel: viewModel,
				repositories: repositories,
				selectedRepositoryID: selectedRepositoryID,
				selectedItem: $sidebarSelection,
				onSelectRepository: onSelectRepository,
				onCloseRepository: onCloseRepository,
				onAddRepository: onAddRepository
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
		.task(id: workingTreeMonitorID) {
			guard scenePhase == .active else { return }
			await viewModel.monitorWorkingTreeChanges()
		}
	}

	private var workingTreeMonitorID: WorkingTreeMonitorID {
		WorkingTreeMonitorID(
			repositoryURL: viewModel.repositoryURL,
			scenePhase: scenePhase
		)
	}
}

private struct WorkingTreeMonitorID: Equatable {
	let repositoryURL: URL?
	let scenePhase: ScenePhase
}

private struct WorkspaceDetail: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		if viewModel.repositoryURL == nil {
			EmptyStateView(
				title: "Open a Git Repository",
				message: "Choose a local repository to inspect changes, history, tags, and files.",
				systemImage: "externaldrive.badge.plus"
			)
		} else {
			switch viewModel.selectedSection ?? .changes {
			case .changes:
				ChangesView(viewModel: viewModel)
			case .history:
				HistoryView(viewModel: viewModel)
			case .branches:
				BranchesView(viewModel: viewModel)
			case .remotes:
				RemotesView(viewModel: viewModel)
			case .stashes:
				StashesView(viewModel: viewModel)
			case .tree:
				RepositoryTreeView(viewModel: viewModel)
			}
		}
	}
}
