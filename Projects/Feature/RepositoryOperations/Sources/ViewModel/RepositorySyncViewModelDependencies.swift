import DomainGitInterface
import Foundation

public struct RepositorySyncViewModelDependencies {
	public let contentUseCase: any RepositoryContentUseCase
	public let referencesUseCase: any RepositoryReferencesUseCase
	public let repositoryURL: @MainActor () -> URL?

	public init(
		contentUseCase: any RepositoryContentUseCase,
		referencesUseCase: any RepositoryReferencesUseCase,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.contentUseCase = contentUseCase
		self.referencesUseCase = referencesUseCase
		self.repositoryURL = repositoryURL
	}
}
