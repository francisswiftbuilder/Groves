import DomainGitInterface
import Foundation

struct DefaultRepositoryStashesUseCase: RepositoryStashesUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func loadDiff(for stash: GitStash, options: GitDiffOptions, at repositoryURL: URL) async throws
		-> String
	{
		try await repository.requestStashDiff(
			for: stash,
			options: options,
			at: repositoryURL
		)
	}

	func loadImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		try await repository.requestStashImageDiff(
			for: stash,
			path: path,
			previousPath: previousPath,
			at: repositoryURL
		)
	}

	func createStash(message: String, includeUntracked: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCreateStash(
			message: message,
			includeUntracked: includeUntracked,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestApplyStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestPopStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDropStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
