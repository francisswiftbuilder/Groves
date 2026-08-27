import DomainGitInterface

public struct ChangesViewModelActions {
	public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
	public let didReceiveError: @MainActor (String) -> Void
	public let didSelectConflict: @MainActor (GitConflict?) -> Void
	public let didSelectDiff: @MainActor (ChangesDiffSelection?, Bool) -> Void

	public init(
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void,
		didSelectConflict: @escaping @MainActor (GitConflict?) -> Void,
		didSelectDiff: @escaping @MainActor (ChangesDiffSelection?, Bool) -> Void
	) {
		self.didProduceSnapshot = didProduceSnapshot
		self.didReceiveError = didReceiveError
		self.didSelectConflict = didSelectConflict
		self.didSelectDiff = didSelectDiff
	}
}
