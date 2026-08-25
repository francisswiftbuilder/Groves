import DomainGitInterface

@MainActor
public protocol RepositoryDIDependencies: AnyObject {
	func makeRepositoryTabsUseCase() throws -> any RepositoryTabsUseCase
	func makeRepositoryContentUseCase() -> any RepositoryContentUseCase
	func makeRepositoryChangesUseCase() -> any RepositoryChangesUseCase
	func makeRepositoryReferencesUseCase() -> any RepositoryReferencesUseCase
	func makeRepositoryStashesUseCase() -> any RepositoryStashesUseCase
	func makeRepositoryOperationsUseCase() -> any RepositoryOperationsUseCase
	func makeRepositoryExternalEditorOpener() -> any RepositoryExternalEditorOpening
}
