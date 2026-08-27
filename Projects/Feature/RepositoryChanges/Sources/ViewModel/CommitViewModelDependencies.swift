import DomainGitInterface
import Foundation

public struct CommitViewModelDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let changesUseCase: any RepositoryChangesUseCase
	let repositoryURL: @MainActor () -> URL?

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
