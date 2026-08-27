import DomainGitInterface

public struct RepositoryOperationViewModelActions {
	public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	public let didReceiveError: @MainActor (String) -> Void
	public let didRequestViewConflicts: @MainActor (GitConflict) -> Void

	public init(
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void,
		didRequestViewConflicts: @escaping @MainActor (GitConflict) -> Void
	) {
		self.didProduceSnapshot = didProduceSnapshot
		self.didReceiveError = didReceiveError
		self.didRequestViewConflicts = didRequestViewConflicts
	}
}
