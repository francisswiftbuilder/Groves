import DomainGitInterface

struct WorkspaceViewModelDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let canAutomaticallyRefresh: @MainActor () -> Bool
}
