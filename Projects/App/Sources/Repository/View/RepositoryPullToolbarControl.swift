import FeatureRepositoryOperations
import SwiftUI

struct RepositoryPullToolbarControl: View {
	private let viewModel: RepositorySyncViewModel

	init(viewModel: RepositorySyncViewModel) {
		self.viewModel = viewModel
	}

	var body: some View {
		if viewModel.presentedActivity?.isPull == true {
			RepositorySyncCancelButton(viewModel: viewModel)
		} else {
			Button {
				viewModel.didRequestPull()
			} label: {
				Label("Pull", systemImage: "arrow.down")
			}
			.disabled(viewModel.isLoading)
			.help("Pull Current Branch")
		}
	}
}
