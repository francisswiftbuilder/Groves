import DomainGit
import DomainGitInterface
import Foundation
import XCTest

@testable import Trees

struct GitRepositoryStub: GitRepository {
	let recorder: GitRepositoryRecorder?
	let changes: [WorkingTreeChange]
	let commits: [GitCommit]
	let branches: [GitBranch]
	let remotes: [GitRemote]
	let operationState: RepositoryOperationState
	let tags: [GitTag]
	let stagedDiff: String
	let unstagedDiff: String
	let clonedRepositoryURL: URL?
	let stashes: [GitStash]
	let stashDiffs: [String: String]
	let diffGate: GitDiffGate?
	let mutationGate: GitDiffGate?
	let contentGate: GitDiffGate?

	init(
		recorder: GitRepositoryRecorder? = nil,
		changes: [WorkingTreeChange] = [],
		commits: [GitCommit] = [],
		branches: [GitBranch] = [],
		remotes: [GitRemote] = [],
		operationState: RepositoryOperationState = .normal,
		tags: [GitTag] = [],
		stagedDiff: String = "",
		unstagedDiff: String = "",
		clonedRepositoryURL: URL? = nil,
		stashes: [GitStash] = [],
		stashDiffs: [String: String] = [:],
		diffGate: GitDiffGate? = nil,
		mutationGate: GitDiffGate? = nil,
		contentGate: GitDiffGate? = nil
	) {
		self.recorder = recorder
		self.changes = changes
		self.commits = commits
		self.branches = branches
		self.remotes = remotes
		self.operationState = operationState
		self.tags = tags
		self.stagedDiff = stagedDiff
		self.unstagedDiff = unstagedDiff
		self.clonedRepositoryURL = clonedRepositoryURL
		self.stashes = stashes
		self.stashDiffs = stashDiffs
		self.diffGate = diffGate
		self.mutationGate = mutationGate
		self.contentGate = contentGate
	}

	func requestRepositoryRoot(at url: URL) async throws -> URL {
		await recorder?.record(.repositoryRoot(url))
		return url
	}
	func requestCloneRepository(from remoteURL: String, into directoryURL: URL) async throws -> URL {
		await recorder?.record(.clone(remoteURL: remoteURL, directoryURL: directoryURL))
		return clonedRepositoryURL
			?? directoryURL.appending(path: "Repository", directoryHint: .isDirectory)
	}
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] {
		await contentGate?.enter(GitDiffGateLabel.workingTreeChanges)
		return changes
	}
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] { [] }
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] { commits }
	func requestCommitDiff(
		for commit: GitCommit,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		await diffGate?.enter(GitDiffGateLabel.commitDiff(hash: commit.hash))
		return ""
	}
	func requestStashDiff(
		for stash: GitStash,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		await diffGate?.enter(GitDiffGateLabel.stash(options: options))
		return stashDiffs[stash.id] ?? GitDiffGateLabel.stashDiff(options: options)
	}
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] { branches }
	func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote] { remotes }
	func requestOperationState(at repositoryURL: URL) async throws -> RepositoryOperationState {
		operationState
	}
	func requestTags(at repositoryURL: URL) async throws -> [GitTag] { tags }
	func requestStashes(at repositoryURL: URL) async throws -> [GitStash] { stashes }
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode] { [] }
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data { Data() }
	func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		await recorder?.record(.loadDiff(source))
		await diffGate?.enter(GitDiffGateLabel.workingTree(options: options))
		return source == .staged ? stagedDiff : unstagedDiff
	}
	func requestAmendDiff(
		for change: GitAmendChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		""
	}
	func requestImageDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		GitImageDiff(before: nil, after: nil)
	}
	func requestAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		GitImageDiff(before: nil, after: nil)
	}
	func requestCommitImageDiff(
		for commit: GitCommit,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		GitImageDiff(before: nil, after: nil)
	}
	func requestStashImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		await diffGate?.enter(GitDiffGateLabel.stashImageDiff(path: path))
		return GitImageDiff(before: nil, after: Data(path.utf8))
	}
	func requestStage(path: String, at repositoryURL: URL) async throws {
		await recorder?.record(.stage(path: path))
		await mutationGate?.enter(GitDiffGateLabel.stage(path: path))
	}
	func requestUnstage(path: String, at repositoryURL: URL) async throws {}
	func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws {
		await recorder?.record(.applyDiffLine(action))
		await mutationGate?.enter(GitDiffGateLabel.applyDiffLine(path: change.path))
	}
	func requestApplyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws {}
	func requestAmendWithoutEditingMessage(at repositoryURL: URL) async throws {}
	func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws {}
	func requestUnstageFromAmend(change: GitAmendChange, at repositoryURL: URL) async throws {}
	func requestCommit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws {}
	func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {
		await recorder?.record(.createBranch(name: name, commitHash: nil))
	}
	func requestCreateBranch(
		named name: String,
		from commitHash: String,
		at repositoryURL: URL
	) async throws {
		await recorder?.record(.createBranch(name: name, commitHash: commitHash))
	}
	func requestCheckoutCommit(_ commitHash: String, at repositoryURL: URL) async throws {
		await recorder?.record(.checkoutCommit(commitHash))
	}
	func requestCreateTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws {}
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestRenameBranch(named name: String, to newName: String, at repositoryURL: URL)
		async throws
	{}
	func requestMergeBranch(named name: String, at repositoryURL: URL) async throws {
		await recorder?.record(.merge(branchName: name))
	}
	func requestRebase(onto branchName: String, at repositoryURL: URL) async throws {}
	func requestCherryPick(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws {}
	func requestRevert(commitHash: String, mainline: Int?, at repositoryURL: URL) async throws {}
	func requestResolveConflict(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws {}
	func requestConflictContent(
		for conflict: GitConflict,
		at repositoryURL: URL
	) async throws -> GitConflictContent {
		await diffGate?.enter(GitDiffGateLabel.conflictContent(path: conflict.path))
		return GitConflictContent(
			base: nil,
			current: nil,
			incoming: nil,
			workingTree: nil,
			hunks: []
		)
	}
	func requestResolveConflictHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution,
		at repositoryURL: URL
	) async throws {
		await mutationGate?.enter(GitDiffGateLabel.resolveConflictHunk(path: conflict.path))
	}

	func requestMarkConflictResolved(path: String, at repositoryURL: URL) async throws {}
	func requestPerformOperationAction(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws {}
	func requestReset(to commitHash: String, mode: GitResetMode, at repositoryURL: URL) async throws {
	}
	func requestCreateTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws {
		await recorder?.record(.createTag(name: name, message: message, commitHash: commitHash))
	}
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {
		await recorder?.record(.deleteTag(name: name))
	}
	func requestCreateStash(
		message: String,
		includeUntracked: Bool,
		at repositoryURL: URL
	) async throws {}
	func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestFetch(remote name: String, at repositoryURL: URL) async throws {}
	func requestFetchAll(at repositoryURL: URL) async throws {}
	func requestPreparePull(at repositoryURL: URL) async throws -> RepositoryPullOutcome {
		.upToDate
	}
	func requestResolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws {}
	func requestPush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		await recorder?.record(.push(target))
	}
	func requestForcePush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		await recorder?.record(.forcePush(target))
	}
	func requestPushTags(remote name: String, at repositoryURL: URL) async throws {
		await recorder?.record(.pushTags(remoteName: name))
	}
	func requestAddRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {}
	func requestRenameRemote(named name: String, to newName: String, at repositoryURL: URL)
		async throws
	{}
	func requestUpdateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {}
	func requestDeleteRemote(named name: String, at repositoryURL: URL) async throws {}
	func requestDeleteRemoteBranch(_ branch: GitRemoteBranch, at repositoryURL: URL) async throws {}
}

@MainActor
func makeRepositoryTabsUseCase(
	repository: any GitRepository = GitRepositoryStub(),
	savedRepositoryStore: any SavedRepositoryStore = SavedRepositoryStoreSpy(repositories: [])
) -> any RepositoryTabsUseCase {
	RepositoryUseCaseFactory.makeTabsUseCase(
		repository: repository,
		savedRepositoryStore: savedRepositoryStore
	)
}

@MainActor
func makeRepositoryWorkspace(
	repository: any GitRepository = GitRepositoryStub(),
	externalEditorOpener: (any RepositoryExternalEditorOpening)? = nil
) -> RepositoryWorkspace {
	RepositoryWorkspaceAssembly(
		dependencies: .init(
			contentUseCase: RepositoryUseCaseFactory.makeContentUseCase(repository: repository),
			changesUseCase: RepositoryUseCaseFactory.makeChangesUseCase(repository: repository),
			referencesUseCase: RepositoryUseCaseFactory.makeReferencesUseCase(repository: repository),
			stashesUseCase: RepositoryUseCaseFactory.makeStashesUseCase(repository: repository),
			operationsUseCase: RepositoryUseCaseFactory.makeOperationsUseCase(repository: repository),
			externalEditorOpener: externalEditorOpener
		)
	)
	.makeWorkspace(repositoryURL: nil)
}

@MainActor
func makeRepositoryTabsViewModel(
	repository: any GitRepository = GitRepositoryStub(),
	savedRepositoryStore: any SavedRepositoryStore = SavedRepositoryStoreSpy(repositories: [])
) -> RepositoryTabsViewModel {
	let contentUseCase = RepositoryUseCaseFactory.makeContentUseCase(repository: repository)
	let changesUseCase = RepositoryUseCaseFactory.makeChangesUseCase(repository: repository)
	let referencesUseCase = RepositoryUseCaseFactory.makeReferencesUseCase(repository: repository)
	let stashesUseCase = RepositoryUseCaseFactory.makeStashesUseCase(repository: repository)
	let workspaceAssembly = RepositoryWorkspaceAssembly(
		dependencies: .init(
			contentUseCase: contentUseCase,
			changesUseCase: changesUseCase,
			referencesUseCase: referencesUseCase,
			stashesUseCase: stashesUseCase,
			operationsUseCase: RepositoryUseCaseFactory.makeOperationsUseCase(repository: repository),
			externalEditorOpener: nil
		)
	)
	return RepositoryTabsViewModel(
		useCase: makeRepositoryTabsUseCase(
			repository: repository,
			savedRepositoryStore: savedRepositoryStore
		),
		makeWorkspace: { repositoryURL in
			workspaceAssembly.makeWorkspace(repositoryURL: repositoryURL)
		}
	)
}
