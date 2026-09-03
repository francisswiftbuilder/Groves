import Foundation

public protocol RepositoryContentUseCase: Sendable {
	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot
	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data
}
