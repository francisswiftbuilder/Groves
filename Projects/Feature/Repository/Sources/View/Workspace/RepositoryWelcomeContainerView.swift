import SwiftUI

struct RepositoryWelcomeContainerView: View {
	@ObservedObject var viewModel: RepositoryWindowViewModel
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: () -> Void
	let onCancel: () -> Void

	var body: some View {
		NavigationSplitView {
			List {}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			RepositoryWelcomeView(
				viewModel: viewModel,
				isWorking: isWorking,
				onOpenRepository: onOpenRepository,
				onCloneRepository: onCloneRepository,
				onCancel: onCancel
			)
		}
	}
}
