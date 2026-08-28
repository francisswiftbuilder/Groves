import CoreRepositoryDiff
import DomainGitInterface
import Foundation

struct StashesViewModelDependencies {
	let useCase: any RepositoryStashesUseCase
	let preferences: WorkspaceDiffPreferences
	let repositoryURL: @MainActor () -> URL?
}
