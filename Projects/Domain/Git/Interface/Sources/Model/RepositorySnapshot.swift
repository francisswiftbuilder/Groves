public struct RepositorySnapshot: Sendable {
	public let changes: [WorkingTreeChange]
	public let amendChanges: [GitAmendChange]
	public let commits: [GitCommit]
	public let branches: [GitBranch]
	public let remotes: [GitRemote]
	public let operationState: RepositoryOperationState
	public let tags: [GitTag]
	public let stashes: [GitStash]
	public let fileTree: [RepositoryTreeNode]

	public init(
		changes: [WorkingTreeChange],
		amendChanges: [GitAmendChange],
		commits: [GitCommit],
		branches: [GitBranch],
		remotes: [GitRemote],
		operationState: RepositoryOperationState,
		tags: [GitTag],
		stashes: [GitStash],
		fileTree: [RepositoryTreeNode]
	) {
		self.changes = changes
		self.amendChanges = amendChanges
		self.commits = commits
		self.branches = branches
		self.remotes = remotes
		self.operationState = operationState
		self.tags = tags
		self.stashes = stashes
		self.fileTree = fileTree
	}
}
