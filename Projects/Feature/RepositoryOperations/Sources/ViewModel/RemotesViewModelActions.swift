import DomainGitInterface

public struct RemotesViewModelActions {
	let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	let didReceiveError: @MainActor (String) -> Void

	public init(
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void
	) {
		self.didProduceSnapshot = didProduceSnapshot
		self.didReceiveError = didReceiveError
	}
}
