import SwiftUI

struct RepositoryWelcomeContainerView: View {
	let isWorking: Bool
	let onOpenRepository: () -> Void
	let onCloneRepository: (String) -> Void

	var body: some View {
		NavigationSplitView {
			List {}
				.listStyle(.sidebar)
				.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			RepositoryWelcomeView(
				isWorking: isWorking,
				onOpenRepository: onOpenRepository,
				onCloneRepository: onCloneRepository
			)
		}
	}
}
