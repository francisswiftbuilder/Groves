import DomainGitInterface
import Foundation

final class GitRepositoryMutationCoordinator: @unchecked Sendable {
	static let shared = GitRepositoryMutationCoordinator()
	private let lock = NSLock()
	private var activeRepositories: Set<URL> = []

	func withMutation<Value: Sendable>(
		at repositoryURL: URL, operation: @Sendable () async throws -> Value
	) async throws -> Value {
		try Task.checkCancellation()
		try lock.withLock {
			guard activeRepositories.insert(repositoryURL).inserted else {
				throw GitRepositoryError.commandFailed(
					"Another operation is changing this repository. Wait for it to finish and retry.")
			}
		}
		defer { _ = lock.withLock { activeRepositories.remove(repositoryURL) } }
		try Task.checkCancellation()
		return try await operation()
	}
}
