import DomainGitInterface
import Foundation

struct ChangesContentUseCaseStub: RepositoryContentUseCase {
	var snapshotOperation: @Sendable (URL) async throws -> RepositorySnapshot = { _ in
		fatalError()
	}

	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await snapshotOperation(repositoryURL)
	}

	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
		fatalError()
	}
}
