import DomainGitInterface

public struct StashesViewModelActions {
	public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	public let didReceiveError: @MainActor (String) -> Void

	public init(
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void
	) {
		self.didProduceSnapshot = didProduceSnapshot
		self.didReceiveError = didReceiveError
	}
}
