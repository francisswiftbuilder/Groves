import DomainGitInterface
import SwiftUI

struct StashesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.stashes.isEmpty {
				EmptyStateView(
					title: "No Stashes",
					message: "Save uncommitted changes to return to them later.",
					systemImage: "archivebox"
				)
			} else {
				List(selection: $viewModel.selectedStashID) {
					ForEach(viewModel.stashes) { stash in
						StashRow(stash: stash)
							.tag(stash.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Stashes")
		.navigationSubtitle("\(viewModel.stashes.count) stashes")
		.safeAreaInset(edge: .bottom) {
			StashActionBar(viewModel: viewModel)
		}
	}
}
