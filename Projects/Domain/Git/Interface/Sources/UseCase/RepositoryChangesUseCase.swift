import Foundation

public protocol RepositoryChangesUseCase: Sendable {
	func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> String
	func loadAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	func loadCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String
	func stage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func unstage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func unstageFromAmend(_ changes: [GitAmendChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func applyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange]
	func discard(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func commit(subject: String, body: String, amend: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	func amendWithoutEditingMessage(at repositoryURL: URL) async throws -> RepositorySnapshot
}
