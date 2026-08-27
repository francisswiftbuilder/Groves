import DomainGitInterface

struct ChangesViewModelActions {
	let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	let didReceiveError: @MainActor (String) -> Void
	let didRequestConfirmation: @MainActor (PendingRepositoryConfirmation) -> Void
}
