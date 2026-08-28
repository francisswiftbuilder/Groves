import DomainGitInterface

struct RepositoryWorkspaceAssemblyDependencies {
	let contentUseCase: any RepositoryContentUseCase
	let changesUseCase: any RepositoryChangesUseCase
	let referencesUseCase: any RepositoryReferencesUseCase
	let stashesUseCase: any RepositoryStashesUseCase
	let operationsUseCase: any RepositoryOperationsUseCase
	let externalEditorOpener: (any RepositoryExternalEditorOpening)?
}
