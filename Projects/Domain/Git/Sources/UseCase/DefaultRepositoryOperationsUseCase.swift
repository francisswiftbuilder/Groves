import DomainGitInterface
import Foundation

public struct DefaultRepositoryOperationsUseCase: RepositoryOperationsUseCase {
	private let repository: any GitRepository
	private let content: any RepositoryContentUseCase

	public init(repository: any GitRepository, content: any RepositoryContentUseCase) {
		self.repository = repository
		self.content = content
	}

	public func rebase(onto branchName: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestRebase(onto: branchName, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func cherryPick(
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

	public func revert(
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

	public func resolve(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestResolveConflict(conflict, using: resolution, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func loadConflictContent(
		for conflict: GitConflict,
		at repositoryURL: URL
	) async throws -> GitConflictContent {
		try await repository.requestConflictContent(for: conflict, at: repositoryURL)
	}

	public func resolveHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestResolveConflictHunk(
			hunk,
			in: conflict,
			using: resolution,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func markResolved(path: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestMarkConflictResolved(path: path, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func perform(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestPerformOperationAction(action, for: operation, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func reset(
		to commitHash: String,
		mode: GitResetMode,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await repository.requestReset(to: commitHash, mode: mode, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
