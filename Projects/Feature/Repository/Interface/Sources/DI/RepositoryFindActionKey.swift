import SwiftUI

private struct RepositoryFindActionKey: FocusedValueKey {
	typealias Value = Binding<Bool>
}

extension FocusedValues {
	public var repositoryFindPresentation: Binding<Bool>? {
		get { self[RepositoryFindActionKey.self] }
		set { self[RepositoryFindActionKey.self] = newValue }
	}
}
