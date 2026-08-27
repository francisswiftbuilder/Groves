import DomainGitInterface
import Foundation

public struct ChangesViewModelDependencies {
	public let contentUseCase: any RepositoryContentUseCase
	public let changesUseCase: any RepositoryChangesUseCase
	public let repositoryURL: @MainActor () -> URL?

	public init(
		contentUseCase: any RepositoryContentUseCase,
		changesUseCase: any RepositoryChangesUseCase,
		repositoryURL: @escaping @MainActor () -> URL?
	) {
		self.contentUseCase = contentUseCase
		self.changesUseCase = changesUseCase
		self.repositoryURL = repositoryURL
	}
}
