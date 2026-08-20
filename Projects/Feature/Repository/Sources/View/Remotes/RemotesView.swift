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

private struct RemoteRow: View {
	let remote: GitRemote

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "icloud.fill")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.blue)
				.frame(width: 20)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(remote.name)
				Text(remote.fetchURL ?? remote.pushURL ?? "No URL")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}

private struct RemoteActionBar: View {
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

			Button("Push", systemImage: "arrow.up") {
				viewModel.didRequestPush()
			}
			.disabled(viewModel.selectedRemote == nil || viewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
