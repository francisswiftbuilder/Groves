import DomainGitInterface
import Foundation

public struct DefaultRepositoryChangesUseCase: RepositoryChangesUseCase {
	private let repository: any GitRepository
	private let content: any RepositoryContentUseCase

	public init(repository: any GitRepository, content: any RepositoryContentUseCase) {
		self.repository = repository
		self.content = content
	}

	public func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		try await repository.requestDiff(
			for: change,
			source: source,
			options: options,
			at: repositoryURL
		)
	}

	public func loadAmendDiff(
		for change: GitAmendChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		try await repository.requestAmendDiff(
			for: change,
			options: options,
			at: repositoryURL
		)
	}

	public func loadCommitDiff(
		for commit: GitCommit,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		try await repository.requestCommitDiff(
			for: commit,
			options: options,
			at: repositoryURL
		)
	}

	public func loadImageDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		try await repository.requestImageDiff(
			for: change,
			source: source,
			at: repositoryURL
		)
	}

	public func loadAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		try await repository.requestAmendImageDiff(for: change, at: repositoryURL)
	}

	public func loadCommitImageDiff(
		for commit: GitCommit,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		try await repository.requestCommitImageDiff(
			for: commit,
			path: path,
			previousPath: previousPath,
			at: repositoryURL
		)
	}

	public func stage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.hasWorkingTreeChange {
			try await repository.requestStage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func unstage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.isStaged {
			try await repository.requestUnstage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func unstageFromAmend(_ changes: [GitAmendChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func applyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		try await repository.requestApplyDiffLine(
			selection,
			action: action,
			for: change,
			at: repositoryURL
		)
		return try await repository.requestWorkingTreeChanges(
			relatedTo: change,
			at: repositoryURL
		)
	}

	public func applyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		try await repository.requestApplyDiffHunk(
			selection,
			action: action,
			for: change,
			options: options,
			at: repositoryURL
		)
		return try await repository.requestWorkingTreeChanges(
			relatedTo: change,
			at: repositoryURL
		)
	}

	public func discard(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestDiscard(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func commit(subject: String, body: String, amend: Bool, at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		try await repository.requestCommit(
			subject: subject,
			body: body,
			amend: amend,
			at: repositoryURL
		)
		return try await content.loadSnapshot(at: repositoryURL)
	}

	public func amendWithoutEditingMessage(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestAmendWithoutEditingMessage(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
