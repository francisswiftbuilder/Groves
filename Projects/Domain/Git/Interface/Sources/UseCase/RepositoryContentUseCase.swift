import Foundation

public protocol RepositoryContentUseCase: Sendable {
	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot
	func refreshWorkingTree(in snapshot: RepositorySnapshot, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data
}

extension RepositoryContentUseCase {
	public func refreshWorkingTree(in snapshot: RepositorySnapshot, at repositoryURL: URL)
		async throws
		-> RepositorySnapshot
	{
		try await loadSnapshot(at: repositoryURL)
	}
}
