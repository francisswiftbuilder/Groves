import SwiftUI

struct RepositoryFocusedActionsModifier: ViewModifier {
	private let viewModel: RepositoryFocusedActionsViewModel

	init(viewModel: RepositoryFocusedActionsViewModel) {
		self.viewModel = viewModel
	}

	func body(content: Content) -> some View {
		content.focusedSceneValue(\.repositoryActions, viewModel.focusedActions)
	}
}
