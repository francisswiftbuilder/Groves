import DomainGitInterface
import Foundation

struct ChangesUseCaseStub: RepositoryChangesUseCase {
	var diffOperation:
		@Sendable (WorkingTreeChange, GitDiffSource, GitDiffOptions, URL) async throws -> String = {
			_, _, _, _ in
			fatalError()
		}
	var commitOperation: @Sendable (String, String, Bool, URL) async throws -> RepositorySnapshot = {
		_, _, _, _ in
		fatalError()
	}
	var amendOperation: @Sendable (URL) async throws -> RepositorySnapshot = { _ in
		fatalError()
	}
	var stageOperation: @Sendable ([WorkingTreeChange], URL) async throws -> RepositorySnapshot = {
		_, _ in
		fatalError()
	}
	var unstageOperation: @Sendable ([WorkingTreeChange], URL) async throws -> RepositorySnapshot = {
		_, _ in
		fatalError()
	}
	var unstageAmendOperation: @Sendable ([GitAmendChange], URL) async throws -> RepositorySnapshot =
		{ _, _ in
			fatalError()
		}

	func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		try await diffOperation(change, source, options, repositoryURL)
	}

	func loadAmendDiff(
		for change: GitAmendChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		fatalError()
	}

	func loadCommitDiff(
		for commit: GitCommit,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		fatalError()
	}

	func loadImageDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		fatalError()
	}

	func loadAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		fatalError()
	}

	func loadCommitImageDiff(
		for commit: GitCommit,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		fatalError()
	}

	func stage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await stageOperation(changes, repositoryURL)
	}

	func unstage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await unstageOperation(changes, repositoryURL)
	}

	func unstageFromAmend(_ changes: [GitAmendChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await unstageAmendOperation(changes, repositoryURL)
	}

	func applyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		fatalError()
	}

	func applyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		fatalError()
	}

	func discard(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		fatalError()
	}

	func commit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws -> RepositorySnapshot {
		try await commitOperation(subject, body, amend, repositoryURL)
	}

	func amendWithoutEditingMessage(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await amendOperation(repositoryURL)
	}
}
