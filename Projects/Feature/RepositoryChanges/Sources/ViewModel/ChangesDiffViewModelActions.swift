import DomainGitInterface

public struct ChangesDiffViewModelActions {
	public let didApplyMutation:
		@MainActor ([WorkingTreeChange], WorkingTreeChange, GitDiffSource) -> Void
	public let didReceiveError: @MainActor (String) -> Void

	public init(
		didApplyMutation:
			@escaping @MainActor (
				[WorkingTreeChange], WorkingTreeChange, GitDiffSource
			) -> Void,
		didReceiveError: @escaping @MainActor (String) -> Void
	) {
		self.didApplyMutation = didApplyMutation
		self.didReceiveError = didReceiveError
	}
}
