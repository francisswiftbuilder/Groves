import DomainGitInterface
import FeatureRepositoryUI
import SwiftUI

public struct RemotesView: View {
	@ObservedObject private var viewModel: RemotesViewModel
	private let syncViewModel: RepositorySyncViewModel

	public init(
		viewModel: RemotesViewModel,
		syncViewModel: RepositorySyncViewModel
	) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
		self.syncViewModel = syncViewModel
	}

	public var body: some View {
		Group {
			if viewModel.remotes.isEmpty {
				EmptyStateView(
					title: "No Remotes",
					message: "Remote repositories will appear here.",
					systemImage: "icloud"
				)
			} else {
				List(
					selection: Binding(
						get: { viewModel.selectedRemoteID },
						set: { viewModel.selectedRemoteID = $0 }
					)
				) {
					ForEach(viewModel.remotes) { remote in
						RemoteRow(remote: remote)
							.tag(remote.id)
							.listRowSeparator(.hidden)
							.contextMenu {
								Button("Rename…", systemImage: "pencil") {
									viewModel.didPresentRename(remote)
								}
								Button("Edit URLs…", systemImage: "link") {
									viewModel.didPresentEditor(remote)
								}
								Divider()
								Button("Delete Remote…", systemImage: "trash", role: .destructive) {
									viewModel.didPresentDeletion(remote)
								}
							}
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Remotes")
		.navigationSubtitle("\(viewModel.remotes.count) remotes")
		.safeAreaInset(edge: .bottom) {
			RemoteActionBar(
				syncViewModel: syncViewModel,
				preferredRemoteName: viewModel.selectedRemote?.name
			) {
				viewModel.didPresentAddRemote()
			}
		}
	}
}
