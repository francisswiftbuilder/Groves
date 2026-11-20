import Foundation

public protocol RepositoryReferencesUseCase: Sendable {
	func pushAction(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState
	) -> RepositoryPushAction
	func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func createBranch(
		named name: String, from source: GitBranchCreationSource, checkout: Bool, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult
	func checkoutCommit(_ commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func deleteBranches(
		localBranches: [GitBranch], remoteBranch: GitRemoteBranch?, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult
	func renameBranch(named name: String, to newName: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func mergeBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func createTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult
	func deleteTag(_ tag: GitTag, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot
	func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot
	func fetchAutomatically(at repositoryURL: URL) async throws
	func preparePull(expecting branch: GitBranch, at repositoryURL: URL) async throws
		-> RepositoryPullPreparation
	func resolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func push(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func forcePush(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func pushTags(remote name: String, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	func addRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func renameRemote(named name: String, to newName: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func updateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot
	func deleteRemote(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
}
