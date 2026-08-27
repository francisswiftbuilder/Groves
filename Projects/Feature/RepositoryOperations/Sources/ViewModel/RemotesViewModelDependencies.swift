import DomainGitInterface
import Foundation

public struct RemotesViewModelDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let referencesUseCase: any RepositoryReferencesUseCase
	let repositoryURL: @MainActor () -> URL?

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
