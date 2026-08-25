import Foundation

public protocol GitRepository: Sendable {
	func requestRepositoryRoot(at url: URL) async throws -> URL
	func requestCloneRepository(from remoteURL: String, into directoryURL: URL) async throws -> URL
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange]
	func requestWorkingTreeChanges(
		relatedTo change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange]
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange]
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit]
	func requestCommitDiff(
		for commit: GitCommit,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String
	func requestStashDiff(
		for stash: GitStash,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch]
	func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote]
	func requestOperationState(at repositoryURL: URL) async throws -> RepositoryOperationState
	func requestTags(at repositoryURL: URL) async throws -> [GitTag]
	func requestStashes(at repositoryURL: URL) async throws -> [GitStash]
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode]
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data
	func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String
	func requestAmendDiff(
		for change: GitAmendChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String
	func requestImageDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> GitImageDiff
	func requestAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff
	func requestCommitImageDiff(
		for commit: GitCommit,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff
	func requestStashImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff
	func requestStage(path: String, at repositoryURL: URL) async throws
	func requestUnstage(path: String, at repositoryURL: URL) async throws
	func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws
	func requestApplyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws
	func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws
	func requestUnstageFromAmend(change: GitAmendChange, at repositoryURL: URL) async throws
	func requestCommit(subject: String, body: String, amend: Bool, at repositoryURL: URL) async throws
	func requestAmendWithoutEditingMessage(at repositoryURL: URL) async throws
	func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws
	func requestCreateBranch(named name: String, at repositoryURL: URL) async throws
	func requestCreateTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws
	func requestRenameBranch(named name: String, to newName: String, at repositoryURL: URL)
		async throws
	func requestMergeBranch(named name: String, at repositoryURL: URL) async throws
	func requestRebase(onto branchName: String, at repositoryURL: URL) async throws
	func requestCherryPick(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws
	func requestRevert(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws
	func requestResolveConflict(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws
	func requestConflictContent(
		for conflict: GitConflict,
		at repositoryURL: URL
	) async throws -> GitConflictContent
	func requestResolveConflictHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution,
		at repositoryURL: URL
	) async throws
	func requestMarkConflictResolved(path: String, at repositoryURL: URL) async throws
	func requestPerformOperationAction(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws
	func requestReset(to commitHash: String, mode: GitResetMode, at repositoryURL: URL) async throws
	func requestCreateTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws
	func requestCreateStash(
		message: String,
		includeUntracked: Bool,
		at repositoryURL: URL
	) async throws
	func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws
	func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws
	func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws
	func requestFetch(remote name: String, at repositoryURL: URL) async throws
	func requestFetchAll(at repositoryURL: URL) async throws
	func requestPull(at repositoryURL: URL) async throws
	func requestPush(_ target: GitPushTarget, at repositoryURL: URL) async throws
	func requestForcePush(_ target: GitPushTarget, at repositoryURL: URL) async throws
	func requestPushTags(remote name: String, at repositoryURL: URL) async throws
	func requestAddRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws
	func requestRenameRemote(named name: String, to newName: String, at repositoryURL: URL)
		async throws
	func requestUpdateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws
	func requestDeleteRemote(named name: String, at repositoryURL: URL) async throws
	func requestDeleteRemoteBranch(_ branch: GitRemoteBranch, at repositoryURL: URL) async throws
}

extension GitRepository {
	public func requestWorkingTreeChanges(
		relatedTo change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		let relatedPaths = Set([change.path, change.previousPath].compactMap { $0 })
		return try await requestWorkingTreeChanges(at: repositoryURL).filter { candidate in
			let candidatePaths = Set([candidate.path, candidate.previousPath].compactMap { $0 })
			return !relatedPaths.isDisjoint(with: candidatePaths)
		}
	}

	public func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws
		-> String
	{
		try await requestCommitDiff(for: commit, options: GitDiffOptions(), at: repositoryURL)
	}

	public func requestStashDiff(for stash: GitStash, at repositoryURL: URL) async throws -> String {
		try await requestStashDiff(for: stash, options: GitDiffOptions(), at: repositoryURL)
	}

	public func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> String {
		try await requestDiff(
			for: change,
			source: source,
			options: GitDiffOptions(),
			at: repositoryURL
		)
	}

	public func requestAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		try await requestAmendDiff(for: change, options: GitDiffOptions(), at: repositoryURL)
	}
}
