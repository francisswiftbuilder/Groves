import SwiftUI

private struct RepositoryFocusedActionsKey: FocusedValueKey {
	typealias Value = RepositoryFocusedActions
}

extension FocusedValues {
	public var repositoryActions: RepositoryFocusedActions? {
		get { self[RepositoryFocusedActionsKey.self] }
		set { self[RepositoryFocusedActionsKey.self] = newValue }
	}
}
