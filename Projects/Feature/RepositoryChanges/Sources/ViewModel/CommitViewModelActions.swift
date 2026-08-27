import DomainGitInterface

public struct CommitViewModelActions {
	let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	let didReceiveError: @MainActor (String) -> Void
	let didChangeAmendingCommit: @MainActor (Bool) -> Void

	public init(
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void,
		didChangeAmendingCommit: @escaping @MainActor (Bool) -> Void
	) {
		self.didProduceSnapshot = didProduceSnapshot
		self.didReceiveError = didReceiveError
		self.didChangeAmendingCommit = didChangeAmendingCommit
	}
}
