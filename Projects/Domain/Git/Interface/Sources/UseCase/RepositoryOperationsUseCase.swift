import Foundation

public protocol RepositoryOperationsUseCase: Sendable {
	func rebase(onto branchName: String, at repositoryURL: URL) async throws -> RepositorySnapshot
	func cherryPick(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func revert(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func resolve(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func markResolved(path: String, at repositoryURL: URL) async throws -> RepositorySnapshot
	func perform(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func reset(
		to commitHash: String,
		mode: GitResetMode,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
}
