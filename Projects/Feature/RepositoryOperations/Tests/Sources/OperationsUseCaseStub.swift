import DomainGitInterface
import Foundation

struct OperationsUseCaseStub: RepositoryOperationsUseCase {
	var resetOperation:
		@Sendable (String, GitResetMode, GitResetContext, URL) async throws -> RepositorySnapshot

	func reset(
		to commitHash: String, mode: GitResetMode, expecting context: GitResetContext,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await resetOperation(commitHash, mode, context, repositoryURL)
	}

	func rebase(onto branchName: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}
	func cherryPick(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{ fatalError() }
	func revert(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{ fatalError() }
	func resolve(
		_ conflict: GitConflict, using resolution: GitConflictResolution, at repositoryURL: URL
	) async throws -> RepositorySnapshot { fatalError() }
	func loadConflictContent(for conflict: GitConflict, at repositoryURL: URL) async throws
		-> GitConflictContent
	{ fatalError() }
	func resolveHunk(
		_ hunk: GitConflictHunk, in conflict: GitConflict, using resolution: GitConflictHunkResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot { fatalError() }
	func markResolved(path: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}
	func perform(
		_ action: RepositoryOperationAction, for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot { fatalError() }
}
