import DomainGitInterface

@MainActor
public struct RepositoryCommitActions {
	public let cherryPick: (GitCommit) -> Void
	public let revert: (GitCommit) -> Void
	public let createBranch: (GitCommit) -> Void
	public let checkoutCommit: (GitCommit) -> Void
	public let createTag: (GitCommit) -> Void
	public let reset: (GitCommit) -> Void

	public init(
		cherryPick: @escaping (GitCommit) -> Void,
		revert: @escaping (GitCommit) -> Void,
		createBranch: @escaping (GitCommit) -> Void,
		checkoutCommit: @escaping (GitCommit) -> Void,
		createTag: @escaping (GitCommit) -> Void,
		reset: @escaping (GitCommit) -> Void
	) {
		self.cherryPick = cherryPick
		self.revert = revert
		self.createBranch = createBranch
		self.checkoutCommit = checkoutCommit
		self.createTag = createTag
		self.reset = reset
	}
}
