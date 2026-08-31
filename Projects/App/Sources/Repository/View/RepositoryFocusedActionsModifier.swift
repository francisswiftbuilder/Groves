import FeatureRepositoryHistory
import FeatureRepositoryOperations
import SwiftUI

struct RepositoryFocusedActionsModifier: ViewModifier {
	@ObservedObject private var historyViewModel: HistoryViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var referencesViewModel: RepositoryReferencesViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel
	let actions: () -> RepositoryFocusedActions

	init(
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		remotesViewModel: RemotesViewModel,
		actions: @escaping () -> RepositoryFocusedActions
	) {
		_historyViewModel = ObservedObject(wrappedValue: historyViewModel)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_referencesViewModel = ObservedObject(wrappedValue: referencesViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
		self.actions = actions
	}

	func body(content: Content) -> some View {
		content.focusedSceneValue(\.repositoryActions, actions())
	}
}
