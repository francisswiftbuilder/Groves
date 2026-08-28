import DomainGitInterface

public struct HistoryViewModelActions {
	public let didReceiveError: @MainActor (String) -> Void
	public let didRequestPresentation: @MainActor () -> Void
	public let didFocusBranch: @MainActor (GitBranch) -> Void
	public let didFocusRemoteBranch: @MainActor (GitRemoteBranch) -> Void

	public init(
		didReceiveError: @escaping @MainActor (String) -> Void,
		didRequestPresentation: @escaping @MainActor () -> Void,
		didFocusBranch: @escaping @MainActor (GitBranch) -> Void,
		didFocusRemoteBranch: @escaping @MainActor (GitRemoteBranch) -> Void
	) {
		self.didReceiveError = didReceiveError
		self.didRequestPresentation = didRequestPresentation
		self.didFocusBranch = didFocusBranch
		self.didFocusRemoteBranch = didFocusRemoteBranch
	}
}
