import DomainGitInterface
import SwiftUI

struct WorkspaceDetail: View {
	@ObservedObject var viewModel: WorkspaceViewModel

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
				.navigationSubtitle(viewModel.currentBranchStatus)
			} else {
				switch viewModel.selectedSection ?? .changes {
				case .changes:
					ChangesView(viewModel: viewModel)
				case .history, .branches:
					HistoryView(viewModel: viewModel)
				case .remotes:
					RemotesView(viewModel: viewModel)
				case .stashes:
					StashesView(viewModel: viewModel)
				case .tree:
					RepositoryTreeView(viewModel: viewModel)
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
				if viewModel.operationState.operation != nil || viewModel.operationState.hasConflicts {
					RepositoryOperationBanner(viewModel: viewModel)
				}
			}
		}
	}
}
