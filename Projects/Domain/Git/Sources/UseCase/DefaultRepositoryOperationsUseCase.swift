import DomainGitInterface
import Foundation

struct DefaultRepositoryOperationsUseCase: RepositoryOperationsUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func rebase(onto branchName: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestRebase(onto: branchName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func cherryPick(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestCherryPick(
			commitHash: commitHash,
			mainline: mainline,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func revert(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestRevert(
			commitHash: commitHash,
			mainline: mainline,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func resolve(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestResolveConflict(conflict, using: resolution, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func markResolved(path: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestMarkConflictResolved(path: path, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func perform(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestPerformOperationAction(action, for: operation, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func reset(
		to commitHash: String,
		mode: GitResetMode,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestReset(to: commitHash, mode: mode, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
