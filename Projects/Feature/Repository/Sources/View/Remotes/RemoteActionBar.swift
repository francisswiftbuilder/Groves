import DomainGitInterface
import SwiftUI

struct RemoteActionBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		HStack(spacing: 10) {
			Label(viewModel.selectedRemote?.name ?? "Remote", systemImage: "icloud")
				.font(.callout)
				.foregroundStyle(.secondary)

			Spacer()

			Button("Pull", systemImage: "arrow.down") {
				viewModel.didRequestPull()
			}
			.disabled(viewModel.selectedRemote == nil || viewModel.isLoading)

			RepositoryPushMenu(
				viewModel: viewModel,
				preferredRemoteName: viewModel.selectedRemote?.name
			)
			.disabled(viewModel.selectedRemote == nil || viewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
