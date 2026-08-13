import DomainGitInterface

@MainActor
public protocol RepositoryDIDependencies: AnyObject {
	func makeGitRepository() -> any GitRepository
	func makeSavedRepositoryStore() throws -> any SavedRepositoryStore
}
