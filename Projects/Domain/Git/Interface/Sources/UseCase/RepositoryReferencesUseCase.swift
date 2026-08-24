import Foundation

public protocol RepositoryReferencesUseCase: Sendable {
	func pushAction(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState
	) -> RepositoryPushAction
	func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func createBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func createTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func createTag(named name: String, message: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func deleteTag(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot
	func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot
	func pull(at repositoryURL: URL) async throws -> RepositorySnapshot
	func push(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
}
