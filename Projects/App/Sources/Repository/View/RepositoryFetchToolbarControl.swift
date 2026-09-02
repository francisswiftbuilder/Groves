import FeatureRepositoryOperations
import SwiftUI

struct RepositoryFetchToolbarControl: View {
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel

	init(
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel
	) {
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
	}

	var body: some View {
		if syncViewModel.presentedActivity?.isFetch == true {
			RepositorySyncCancelButton(viewModel: syncViewModel)
		} else {
			Menu {
				Button("Fetch All Remotes", systemImage: "arrow.triangle.2.circlepath") {
					syncViewModel.didRequestFetchAll()
				}

				if !remotesViewModel.remotes.isEmpty {
					Divider()
					ForEach(remotesViewModel.remotes) { remote in
						Button(remote.name, systemImage: "icloud.and.arrow.down") {
							syncViewModel.didRequestFetch(remoteName: remote.name)
						}
					}
				}
			} label: {
				Label("Fetch", systemImage: "arrow.triangle.2.circlepath")
			}
			.accessibilityLabel("Fetch")
			.disabled(syncViewModel.isLoading || remotesViewModel.remotes.isEmpty)
			.help("Fetch Remote References")
		}
	}
}
