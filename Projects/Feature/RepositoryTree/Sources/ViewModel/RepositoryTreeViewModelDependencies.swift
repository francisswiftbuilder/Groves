import DomainGitInterface

public struct RepositoryTreeViewModelDependencies {
	public let contentUseCase: any RepositoryContentUseCase

	public init(contentUseCase: any RepositoryContentUseCase) {
		self.contentUseCase = contentUseCase
	}
}
