import DomainGitInterface
import Foundation

actor StashesUseCaseStub: RepositoryStashesUseCase {
	private let diffs: [String: String]
	private let gate: StashesUseCaseGate?

	init(
		diffs: [String: String] = [:],
		gate: StashesUseCaseGate? = nil
	) {
		self.diffs = diffs
		self.gate = gate
	}

	func loadDiff(
		for stash: GitStash,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		await gate?.enter()
		return diffs[stash.id] ?? ""
	}

	func loadImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		await gate?.enter()
		return GitImageDiff(before: nil, after: Data(path.utf8))
	}

	func createStash(
		message: String,
		includeUntracked: Bool,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		fatalError()
	}

	func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}
}
