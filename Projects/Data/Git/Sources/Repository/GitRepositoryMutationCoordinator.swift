import DomainGitInterface
import Foundation

actor GitRepositoryMutationCoordinator {
	static let shared = GitRepositoryMutationCoordinator()
	private var activeRepositories: Set<URL> = []

	func withMutation<Value: Sendable>(
		at repositoryURL: URL, operation: @Sendable () async throws -> Value
	) async throws -> Value {
		try Task.checkCancellation()
		guard activeRepositories.insert(repositoryURL).inserted else {
			throw GitRepositoryError.commandFailed(
				"Another operation is changing this repository. Wait for it to finish and retry.")
		}
		defer { activeRepositories.remove(repositoryURL) }
		try Task.checkCancellation()
		return try await operation()
	}
}
