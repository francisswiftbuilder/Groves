import SwiftUI

private struct RepositoryFindActionKey: FocusedValueKey {
	typealias Value = any RepositoryFindActions
}

extension FocusedValues {
	public var repositoryFindActions: (any RepositoryFindActions)? {
		get { self[RepositoryFindActionKey.self] }
		set { self[RepositoryFindActionKey.self] = newValue }
	}
}
