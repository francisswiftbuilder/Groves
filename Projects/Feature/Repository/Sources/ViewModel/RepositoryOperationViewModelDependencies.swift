import DomainGitInterface
import Foundation

struct RepositoryOperationViewModelDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let referencesUseCase: any RepositoryReferencesUseCase
	let operationsUseCase: (any RepositoryOperationsUseCase)?
	let repositoryURL: @MainActor () -> URL?
}
