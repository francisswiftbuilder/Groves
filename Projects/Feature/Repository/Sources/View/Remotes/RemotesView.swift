import DomainGitInterface
import SwiftUI

struct RemotesView: View {
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel

	init(viewModel: RepositoryOperationViewModel) {
		_operationViewModel = ObservedObject(wrappedValue: viewModel)
	}

	var body: some View {
		Group {
			if operationViewModel.remotes.isEmpty {
				EmptyStateView(
					title: "No Remotes",
					message: "Remote repositories will appear here.",
					systemImage: "icloud"
				)
			} else {
				List(
					selection: Binding(
						get: { operationViewModel.selectedRemoteID },
						set: { operationViewModel.selectedRemoteID = $0 }
					)
				) {
					ForEach(operationViewModel.remotes) { remote in
						RemoteRow(remote: remote)
							.tag(remote.id)
							.listRowSeparator(.hidden)
							.contextMenu {
								Button("Rename…", systemImage: "pencil") {
									operationViewModel.didPresentRemoteRename(remote)
								}
								Button("Edit URLs…", systemImage: "link") {
									operationViewModel.didPresentRemoteEditor(remote)
								}
								Divider()
								Button("Delete Remote…", systemImage: "trash", role: .destructive) {
									operationViewModel.didPresentRemoteDeletion(remote)
								}
							}
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("Remotes")
		.navigationSubtitle("\(operationViewModel.remotes.count) remotes")
		.safeAreaInset(edge: .bottom) {
			RemoteActionBar(operationViewModel: operationViewModel) {
				operationViewModel.didPresentAddRemote()
			}
		}
	}
}
