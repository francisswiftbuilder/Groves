import SwiftUI

struct RepositoryFocusedActionsModifier: ViewModifier {
	@ObservedObject private var viewModel: RepositoryFocusedActionsViewModel

	init(viewModel: RepositoryFocusedActionsViewModel) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
	}

	func body(content: Content) -> some View {
		content.focusedSceneValue(\.repositoryActions, viewModel.focusedActions)
	}
}
