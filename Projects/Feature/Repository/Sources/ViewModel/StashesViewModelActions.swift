import DomainGitInterface

struct StashesViewModelActions {
	let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	let didReceiveError: @MainActor (String) -> Void
	let didRequestDropConfirmation: @MainActor (GitStash) -> Void
}
