import DomainGitInterface
import Foundation

struct DefaultRepositoryContentUseCase: RepositoryContentUseCase {
	let repository: any GitRepository

	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot {
		async let changes = repository.requestWorkingTreeChanges(at: repositoryURL)
		async let amendChanges = repository.requestAmendChanges(at: repositoryURL)
		async let commits = repository.requestCommitHistory(at: repositoryURL)
		async let branches = repository.requestBranches(at: repositoryURL)
		async let remotes = repository.requestRemotes(at: repositoryURL)
		async let operationState = repository.requestOperationState(at: repositoryURL)
		async let tags = repository.requestTags(at: repositoryURL)
		async let stashes = repository.requestStashes(at: repositoryURL)
		async let fileTree = repository.requestFileTree(at: repositoryURL)

		return try await RepositorySnapshot(
			changes: changes,
			amendChanges: amendChanges,
			commits: commits,
			branches: branches,
			remotes: remotes,
			operationState: operationState,
			tags: tags,
			stashes: stashes,
			fileTree: fileTree
		)
	}

	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
		try await repository.requestFileContents(at: path, in: repositoryURL)
	}
}
