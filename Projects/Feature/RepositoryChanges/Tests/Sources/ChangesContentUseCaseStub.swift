import DomainGitInterface
import Foundation

struct ChangesContentUseCaseStub: RepositoryContentUseCase {
	func loadSnapshot(at repositoryURL: URL) async throws -> RepositorySnapshot {
		fatalError()
	}

	func loadFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
		fatalError()
	}
}
