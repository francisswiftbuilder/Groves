import SwiftUI

private struct RepositoryWindowTabCoordinatorKey: EnvironmentKey {
	static let defaultValue: (any RepositoryWindowTabCoordinating)? = nil
}

extension EnvironmentValues {
	@MainActor
	var windowTabCoordinator: (any RepositoryWindowTabCoordinating)? {
		get { self[RepositoryWindowTabCoordinatorKey.self] }
		set { self[RepositoryWindowTabCoordinatorKey.self] = newValue }
	}
}
