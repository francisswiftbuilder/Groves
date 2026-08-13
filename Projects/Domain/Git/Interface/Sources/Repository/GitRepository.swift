import Foundation

public protocol GitRepository: Sendable {
	func requestRepositoryRoot(at url: URL) async throws -> URL
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange]
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit]
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch]
	func requestTags(at repositoryURL: URL) async throws -> [GitTag]
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode]
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data
	func requestDiff(for change: WorkingTreeChange, at repositoryURL: URL) async throws -> String
	func requestStage(path: String, at repositoryURL: URL) async throws
	func requestUnstage(path: String, at repositoryURL: URL) async throws
	func requestCommit(message: String, at repositoryURL: URL) async throws
	func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws
	func requestCreateBranch(named name: String, at repositoryURL: URL) async throws
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws
	func requestCreateTag(named name: String, message: String, at repositoryURL: URL) async throws
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws
	func requestPull(at repositoryURL: URL) async throws
	func requestPush(at repositoryURL: URL) async throws
}
