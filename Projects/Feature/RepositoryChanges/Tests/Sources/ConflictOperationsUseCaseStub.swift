import DomainGitInterface
import Foundation

struct ConflictOperationsUseCaseStub: RepositoryOperationsUseCase {
	var conflictContentOperation: @Sendable (GitConflict, URL) async throws -> GitConflictContent = {
		_, _ in
		fatalError()
	}

	var resolveOperation:
		@Sendable (GitConflict, GitConflictResolution, GitConflictContent, URL) async throws ->
			RepositorySnapshot = {
				_, _, _, _ in fatalError()
			}

	func loadConflictContent(
		for conflict: GitConflict,
		at repositoryURL: URL
	) async throws -> GitConflictContent {
		try await conflictContentOperation(conflict, repositoryURL)
	}

	func rebase(onto branchName: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}

	func cherryPick(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func revert(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func resolve(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		expecting content: GitConflictContent,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await resolveOperation(conflict, resolution, content, repositoryURL)
	}

	func resolveHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution,
		expecting expectedContents: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func markResolved(path: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}

	func perform(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func reset(
		to commitHash: String,
		mode: GitResetMode,
		expecting context: GitResetContext,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}
}
