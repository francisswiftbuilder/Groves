import DomainGitInterface
import Foundation

public struct RepositoryOperationViewModelDependencies {
	public let contentUseCase: any RepositoryContentUseCase
	public let referencesUseCase: any RepositoryReferencesUseCase
	public let operationsUseCase: (any RepositoryOperationsUseCase)?
	public let repositoryURL: @MainActor () -> URL?

	public init(
		contentUseCase: any RepositoryContentUseCase,
		referencesUseCase: any RepositoryReferencesUseCase,
		operationsUseCase: (any RepositoryOperationsUseCase)?,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.contentUseCase = contentUseCase
		self.referencesUseCase = referencesUseCase
		self.operationsUseCase = operationsUseCase
		self.repositoryURL = repositoryURL
	}
}
