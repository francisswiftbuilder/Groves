import DomainGitInterface
import FeatureRepositoryInterface
import Foundation

struct ChangesViewModelDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let changesUseCase: any RepositoryChangesUseCase
	let operationsUseCase: (any RepositoryOperationsUseCase)?
	let externalEditorOpener: (any RepositoryExternalEditorOpening)?
	let preferences: WorkspaceDiffPreferences
	let repositoryURL: @MainActor () -> URL?
}
