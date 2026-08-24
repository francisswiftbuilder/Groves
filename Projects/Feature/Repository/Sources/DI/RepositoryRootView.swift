import FeatureRepositoryInterface
import Foundation
import SwiftUI

struct RepositoryRootView: View {
	@ObservedObject var viewModel: RepositoryTabsViewModel
	@Binding var repositoryID: UUID?
	@StateObject private var windowViewModel = RepositoryWindowViewModel()

	var body: some View {
		RepositoryTabsView(
			viewModel: viewModel,
			windowViewModel: windowViewModel,
			repositoryID: $repositoryID
		)
	}
}
