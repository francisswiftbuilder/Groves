import DomainGitInterface

struct RepositoryOperationViewModelActions {
	let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	let didReceiveError: @MainActor (String) -> Void
	let didRequestConfirmation: @MainActor (PendingRepositoryConfirmation) -> Void
	let didRequestViewConflicts: @MainActor (GitConflict) -> Void
}
