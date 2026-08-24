import Foundation

public protocol RepositoryStashesUseCase: Sendable {
	func createStash(message: String, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func applyStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func popStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func dropStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> RepositorySnapshot
}
