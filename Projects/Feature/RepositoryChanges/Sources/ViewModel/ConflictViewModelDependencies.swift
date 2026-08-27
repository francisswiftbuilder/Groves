import DomainGitInterface
import Foundation

public struct ConflictViewModelDependencies {
	public let contentUseCase: any RepositoryContentUseCase
	public let operationsUseCase: any RepositoryOperationsUseCase
	public let openExternalEditor: (@MainActor (URL, String?) throws -> Void)?
	public let repositoryURL: @MainActor () -> URL?

	public init(
		contentUseCase: any RepositoryContentUseCase,
		operationsUseCase: any RepositoryOperationsUseCase,
		openExternalEditor: (@MainActor (URL, String?) throws -> Void)?,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.contentUseCase = contentUseCase
		self.operationsUseCase = operationsUseCase
		self.openExternalEditor = openExternalEditor
		self.repositoryURL = repositoryURL
	}
}
