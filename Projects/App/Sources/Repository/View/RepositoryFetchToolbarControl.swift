import FeatureRepositoryOperations
import SwiftUI

struct RepositoryFetchToolbarControl: View {
	private let syncViewModel: RepositorySyncViewModel
	private let remotesViewModel: RemotesViewModel

	init(
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel
	) {
		self.syncViewModel = syncViewModel
		self.remotesViewModel = remotesViewModel
	}

	var body: some View {
		if syncViewModel.presentedActivity?.isFetch == true {
			RepositorySyncCancelButton(viewModel: syncViewModel)
		} else {
			Group {
				if remotesViewModel.remotes.count > 1 {
					Menu {
						Button("Fetch All Remotes", systemImage: "arrow.down.to.line") {
							syncViewModel.didRequestFetchAll()
						}
						Divider()
						ForEach(remotesViewModel.remotes) { remote in
							Button(remote.name, systemImage: "icloud.and.arrow.down") {
								syncViewModel.didRequestFetch(remoteName: remote.name)
							}
						}
					} label: {
						Label("Fetch", systemImage: "arrow.down.to.line")
					} primaryAction: {
						syncViewModel.didRequestFetchAll()
					}
				} else {
					Button("Fetch", systemImage: "arrow.down.to.line") {
						syncViewModel.didRequestFetchAll()
					}
				}
			}
			.accessibilityLabel("Fetch")
			.disabled(!syncViewModel.canFetch)
			.help("Fetch Remote References")
		}
	}
}
