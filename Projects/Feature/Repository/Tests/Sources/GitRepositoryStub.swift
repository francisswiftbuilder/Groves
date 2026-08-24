import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

struct GitRepositoryStub: GitRepository {
	let commits: [GitCommit]
	let remotes: [GitRemote]
	let tags: [GitTag]
	let clonedRepositoryURL: URL?

	init(
		commits: [GitCommit] = [],
		remotes: [GitRemote] = [],
		tags: [GitTag] = [],
		clonedRepositoryURL: URL? = nil
	) {
		self.commits = commits
		self.remotes = remotes
		self.tags = tags
		self.clonedRepositoryURL = clonedRepositoryURL
	}

	func requestRepositoryRoot(at url: URL) async throws -> URL { url }
	func requestCloneRepository(from remoteURL: String, into directoryURL: URL) async throws -> URL {
		clonedRepositoryURL ?? directoryURL.appending(path: "Repository", directoryHint: .isDirectory)
	}
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] { [] }
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] { [] }
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] { commits }
	func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String { "" }
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] { [] }
	func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote] { remotes }
	func requestTags(at repositoryURL: URL) async throws -> [GitTag] { tags }
	func requestStashes(at repositoryURL: URL) async throws -> [GitStash] { [] }
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode] { [] }
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data { Data() }
	func requestDiff(for change: WorkingTreeChange, at repositoryURL: URL) async throws -> String {
		""
	}
	func requestAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		""
	}
	func requestStage(path: String, at repositoryURL: URL) async throws {}
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
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateTag(named name: String, message: String, at repositoryURL: URL) async throws {}
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateStash(message: String, at repositoryURL: URL) async throws {}
	func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPull(at repositoryURL: URL) async throws {}
	func requestPush(at repositoryURL: URL) async throws {}
}
