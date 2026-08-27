import DomainGitInterface
import Foundation

struct DefaultRepositoryChangesUseCase: RepositoryChangesUseCase {
	let repository: any GitRepository
	let content: any RepositoryContentUseCase

	func loadDiff(
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

	func loadAmendDiff(
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

	func loadCommitDiff(
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

	func loadImageDiff(
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

	func loadAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		try await repository.requestAmendImageDiff(for: change, at: repositoryURL)
	}

	func loadCommitImageDiff(
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

	func stage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.hasWorkingTreeChange {
			try await repository.requestStage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func unstage(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes where change.isStaged {
			try await repository.requestUnstage(path: change.path, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func unstageFromAmend(_ changes: [GitAmendChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func applyDiffLine(
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

	func applyDiffHunk(
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

	func discard(_ changes: [WorkingTreeChange], at repositoryURL: URL) async throws
		-> RepositorySnapshot
	{
		for change in changes {
			try await repository.requestDiscard(change: change, at: repositoryURL)
		}
		return try await content.loadSnapshot(at: repositoryURL)
	}

	func commit(subject: String, body: String, amend: Bool, at repositoryURL: URL) async throws
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

	func amendWithoutEditingMessage(at repositoryURL: URL) async throws -> RepositorySnapshot {
		try await repository.requestAmendWithoutEditingMessage(at: repositoryURL)
		return try await content.loadSnapshot(at: repositoryURL)
	}
}
