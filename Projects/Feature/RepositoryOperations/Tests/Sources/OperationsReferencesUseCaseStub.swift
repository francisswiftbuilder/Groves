import DomainGitInterface
import Foundation

struct OperationsReferencesUseCaseStub: RepositoryReferencesUseCase {
	let fetchAllOperation: @Sendable (URL) async throws -> RepositorySnapshot

	init(
		fetchAllOperation: @escaping @Sendable (URL) async throws -> RepositorySnapshot = { _ in
			fatalError()
		}
	) {
		self.fetchAllOperation = fetchAllOperation
	}

	func pushAction(
		currentBranch: GitBranch?,
		remotes: [GitRemote],
		operationState: RepositoryOperationState
	) -> RepositoryPushAction {
		fatalError()
	}

	func switchBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func createBranch(named name: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func createBranch(
		named name: String,
		from commitHash: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
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
		fatalError()
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
		fatalError()
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
		fatalError()
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
		fatalError()
	}

	func renameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func updateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
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
