import DomainGit
import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

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
		clonedRepositoryURL: URL? = nil
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
		changes
	}
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] { [] }
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] { commits }
	func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String { "" }
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] { branches }
	func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote] { remotes }
	func requestOperationState(at repositoryURL: URL) async throws -> RepositoryOperationState {
		operationState
	}
	func requestTags(at repositoryURL: URL) async throws -> [GitTag] { tags }
	func requestStashes(at repositoryURL: URL) async throws -> [GitStash] { [] }
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode] { [] }
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data { Data() }
	func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> String {
		source == .staged ? stagedDiff : unstagedDiff
	}
	func requestAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		""
	}
	func requestStage(path: String, at repositoryURL: URL) async throws {
		await recorder?.record(.stage(path: path))
	}
	func requestUnstage(path: String, at repositoryURL: URL) async throws {}
	func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws {}
	func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws {}
	func requestUnstageFromAmend(change: GitAmendChange, at repositoryURL: URL) async throws {}
	func requestCommit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws {}
	func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws {}
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateTag(named name: String, message: String, at repositoryURL: URL) async throws {}
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateStash(message: String, at repositoryURL: URL) async throws {}
	func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestFetch(remote name: String, at repositoryURL: URL) async throws {}
	func requestFetchAll(at repositoryURL: URL) async throws {}
	func requestPull(at repositoryURL: URL) async throws {}
	func requestPush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		await recorder?.record(.push(target))
	}
}

actor GitRepositoryRecorder {
	enum Event: Equatable, Sendable {
		case repositoryRoot(URL)
		case clone(remoteURL: String, directoryURL: URL)
		case stage(path: String)
		case push(GitPushTarget)
	}

	private var events: [Event] = []

	func record(_ event: Event) {
		events.append(event)
	}

	func recordedEvents() -> [Event] {
		events
	}
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
func makeWorkspaceViewModel(
	repository: any GitRepository = GitRepositoryStub()
) -> WorkspaceViewModel {
	WorkspaceViewModel(
		contentUseCase: RepositoryUseCaseFactory.makeContentUseCase(repository: repository),
		changesUseCase: RepositoryUseCaseFactory.makeChangesUseCase(repository: repository),
		referencesUseCase: RepositoryUseCaseFactory.makeReferencesUseCase(repository: repository),
		stashesUseCase: RepositoryUseCaseFactory.makeStashesUseCase(repository: repository)
	)
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
	return RepositoryTabsViewModel(
		useCase: makeRepositoryTabsUseCase(
			repository: repository,
			savedRepositoryStore: savedRepositoryStore
		),
		makeWorkspaceViewModel: { repositoryURL in
			WorkspaceViewModel(
				contentUseCase: contentUseCase,
				changesUseCase: changesUseCase,
				referencesUseCase: referencesUseCase,
				stashesUseCase: stashesUseCase,
				repositoryURL: repositoryURL
			)
		}
	)
}
