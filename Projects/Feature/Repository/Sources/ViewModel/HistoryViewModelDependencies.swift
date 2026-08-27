import DomainGitInterface
import Foundation

struct HistoryViewModelDependencies {
	let changesUseCase: any RepositoryChangesUseCase
	let preferences: WorkspaceDiffPreferences
	let repositoryURL: @MainActor () -> URL?
}
