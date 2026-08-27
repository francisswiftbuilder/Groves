import DomainGitInterface
import FeatureRepositoryInterface

public struct HistoryViewModelActions {
	public let didReceiveError: @MainActor (String) -> Void
	public let didSelectSection: @MainActor (WorkspaceSection) -> Void
	public let didFocusBranch: @MainActor (GitBranch) -> Void
	public let didFocusRemoteBranch: @MainActor (GitRemoteBranch) -> Void

	public init(
		didReceiveError: @escaping @MainActor (String) -> Void,
		didSelectSection: @escaping @MainActor (WorkspaceSection) -> Void,
		didFocusBranch: @escaping @MainActor (GitBranch) -> Void,
		didFocusRemoteBranch: @escaping @MainActor (GitRemoteBranch) -> Void
	) {
		self.didReceiveError = didReceiveError
		self.didSelectSection = didSelectSection
		self.didFocusBranch = didFocusBranch
		self.didFocusRemoteBranch = didFocusRemoteBranch
	}
}
