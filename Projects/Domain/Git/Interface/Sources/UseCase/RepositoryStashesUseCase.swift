import Foundation

public protocol RepositoryStashesUseCase: Sendable {
	func loadDiff(for stash: GitStash, at repositoryURL: URL) async throws -> String
	func createStash(message: String, includeUntracked: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
}
