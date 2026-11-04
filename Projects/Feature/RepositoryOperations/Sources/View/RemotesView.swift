import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

public struct RemotesView: View {
	private let viewModel: RemotesViewModel
	private let syncViewModel: RepositorySyncViewModel

	public init(
		viewModel: RemotesViewModel,
		syncViewModel: RepositorySyncViewModel
	) {
		self.viewModel = viewModel
		self.syncViewModel = syncViewModel
	}

	public var body: some View {
		Group {
			if viewModel.remotes.isEmpty {
				EmptyStateView(
					title: "No Remotes",
					message: "Add a remote to sync this repository.",
					systemImage: "network"
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
		.safeAreaInset(edge: .top, spacing: 0) {
			VStack(spacing: 0) {
				HStack {
					Text("Remotes").font(.headline)
					Spacer()
					Text("\(viewModel.remotes.count)").foregroundStyle(.secondary)
				}
				.padding(.horizontal, 12)
				.frame(height: 52)
				.background(.bar)
				Divider()
			}
		}
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
