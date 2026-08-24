import DomainGitInterface
import SwiftUI

struct RemotesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.remotes.isEmpty {
				EmptyStateView(
					title: "No Remotes",
					message: "Remote repositories will appear here.",
					systemImage: "icloud"
				)
			} else {
				List(selection: $viewModel.selectedRemoteID) {
					ForEach(viewModel.remotes) { remote in
						RemoteRow(remote: remote)
							.tag(remote.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Remotes")
		.navigationSubtitle("\(viewModel.remotes.count) remotes")
		.safeAreaInset(edge: .bottom) {
			RemoteActionBar(viewModel: viewModel)
		}
	}
}
