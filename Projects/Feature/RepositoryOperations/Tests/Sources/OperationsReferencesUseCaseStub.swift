import DomainGitInterface
import Foundation

struct OperationsReferencesUseCaseStub: RepositoryReferencesUseCase {
	var deleteBranchesOperation:
		@Sendable ([GitBranch], GitRemoteBranch?, URL) async throws -> RepositoryReferenceMutationResult =
			{
				_, _, _ in fatalError()
			}
	var createBranchOperation: @Sendable (String, String?, URL) async throws -> RepositorySnapshot = {
		_, _, _ in fatalError()
	}
	var createTagOperation:
		@Sendable (String, String, String, URL) async throws -> RepositorySnapshot = { _, _, _, _ in
			fatalError()
		}
	var renameBranchOperation: @Sendable (String, String, URL) async throws -> RepositorySnapshot = {
		_, _, _ in fatalError()
	}
	var addRemoteOperation:
		@Sendable (String, String, String?, URL) async throws -> RepositorySnapshot = { _, _, _, _ in
			fatalError()
		}
	var updateRemoteOperation:
		@Sendable (String, String, String?, URL) async throws -> RepositorySnapshot = { _, _, _, _ in
			fatalError()
		}
	var renameRemoteOperation: @Sendable (String, String, URL) async throws -> RepositorySnapshot = {
		_, _, _ in fatalError()
	}
	var pushOperation: @Sendable (URL) async throws -> RepositorySnapshot = { _ in
		fatalError()
	}
	var preparePullOperation: @Sendable (URL) async throws -> RepositoryPullPreparation = { _ in
		fatalError()
	}
	var fetchAllInteractionHandler: @Sendable (Bool) -> Void = { _ in }
	let fetchAllOperation: @Sendable (URL) async throws -> RepositorySnapshot
	let pushActionOperation:
		@Sendable (GitBranch?, [GitRemote], RepositoryOperationState) -> RepositoryPushAction

	init(
		fetchAllOperation: @escaping @Sendable (URL) async throws -> RepositorySnapshot = { _ in
			fatalError()
		},
		pushActionOperation:
			@escaping @Sendable (
				GitBranch?,
				[GitRemote],
				RepositoryOperationState
			) -> RepositoryPushAction = { _, _, _ in .unavailable }
	) {
		self.fetchAllOperation = fetchAllOperation
		self.pushActionOperation = pushActionOperation
	}

	func pushAction(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState
	) -> RepositoryPushAction {
		pushActionOperation(currentBranch, remotes, operationState)
	}

	func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func createBranch(
		named name: String, from source: GitBranchCreationSource, checkout: Bool, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		let hash: String?
		if case .commit(let commit) = source { hash = commit } else { hash = nil }
		return .init(snapshot: try await createBranchOperation(name, hash, repositoryURL))
	}

	func checkoutCommit(_ commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func deleteBranches(
		localBranches: [GitBranch], remoteBranch: GitRemoteBranch?, at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		try await deleteBranchesOperation(localBranches, remoteBranch, repositoryURL)
	}

	func renameBranch(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await renameBranchOperation(name, newName, repositoryURL)
	}

	func mergeBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func createTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositoryReferenceMutationResult {
		.init(snapshot: try await createTagOperation(name, message, commitHash, repositoryURL))
	}

	func deleteTag(_ tag: GitTag, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	{
		fatalError()
	}

	func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}

	func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot {
		fetchAllInteractionHandler(true)
		return try await fetchAllOperation(repositoryURL)
	}

	func fetchAutomatically(at repositoryURL: URL) async throws {
		fetchAllInteractionHandler(false)
		_ = try await fetchAllOperation(repositoryURL)
	}

	func preparePull(expecting branch: GitBranch, at repositoryURL: URL) async throws
		-> RepositoryPullPreparation
	{
		try await preparePullOperation(repositoryURL)
	}

	func resolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func push(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await pushOperation(repositoryURL)
	}

	func forcePush(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		selectedRemoteName: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func pushTags(remote name: String, at repositoryURL: URL) async throws
		-> RepositoryReferenceMutationResult
	{
		fatalError()
	}

	func addRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await addRemoteOperation(name, fetchURL, pushURL, repositoryURL)
	}

	func renameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await renameRemoteOperation(name, newName, repositoryURL)
	}

	func updateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await updateRemoteOperation(name, fetchURL, pushURL, repositoryURL)
	}

	func deleteRemote(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

}
