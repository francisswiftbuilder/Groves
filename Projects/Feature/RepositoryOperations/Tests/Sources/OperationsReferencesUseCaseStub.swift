import DomainGitInterface
import Foundation

struct OperationsReferencesUseCaseStub: RepositoryReferencesUseCase {
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

	func createBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await createBranchOperation(name, nil, repositoryURL)
	}

	func createBranch(
		named name: String,
		from commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await createBranchOperation(name, commitHash, repositoryURL)
	}

	func checkoutCommit(_ commitHash: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func createTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func deleteBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
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
	) async throws -> RepositorySnapshot {
		try await createTagOperation(name, message, commitHash, repositoryURL)
	}

	func deleteTag(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func fetch(remote name: String, at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}

	func fetchAll(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await fetchAllOperation(repositoryURL)
	}

	func preparePull(at repositoryURL: URL) async throws -> RepositoryPullPreparation {
		fatalError()
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
		-> RepositorySnapshot
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

	func deleteRemoteBranch(_ branch: GitRemoteBranch, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}
}
