import DomainGitInterface
import Foundation

public struct DefaultRepositoryStashesUseCase: RepositoryStashesUseCase {
	private let repository: any GitRepository
	private let content: any RepositoryContentUseCase

	public init(repository: any GitRepository, content: any RepositoryContentUseCase) {
		self.repository = repository
		self.content = content
	}

	public func loadDiff(for stash: GitStash, options: GitDiffOptions, at repositoryURL: URL)
		async throws
		-> String
	{
		try await repository.requestStashDiff(
			for: stash,
			options: options,
			at: repositoryURL
		)
	}

	public func loadImageDiff(
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

	public func createStash(message: String, includeUntracked: Bool, at repositoryURL: URL)
		async throws
		-> RepositorySnapshot
	{
		try await repository.requestCreateStash(
			message: message,
			includeUntracked: includeUntracked,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestApplyStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestPopStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestDropStash(stash, at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
