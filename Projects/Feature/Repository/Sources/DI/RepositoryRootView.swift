import FeatureRepositoryInterface
import Foundation
import SwiftUI

struct RepositoryRootView: View {
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@Binding var repositoryID: UUID?

	var body: some View {
		RepositoryTabsView(
			viewModel: viewModel,
			repositoryID: $repositoryID
		)
	}
}
