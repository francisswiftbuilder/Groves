import DomainGitInterface

struct HistoryViewModelActions {
	let didReceiveError: @MainActor (String) -> Void
	let didSelectSection: @MainActor (WorkspaceSection) -> Void
	let didFocusBranch: @MainActor (GitBranch) -> Void
	let didFocusRemoteBranch: @MainActor (GitRemoteBranch) -> Void
}
