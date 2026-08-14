import DomainGitInterface
import Foundation

public struct LocalGitRepository: GitRepository {
	private static let maximumPreviewByteCount = 10 * 1_024 * 1_024
	private let runner: GitProcessRunner

	public init() {
		runner = GitProcessRunner()
	}

	init(runner: GitProcessRunner) {
		self.runner = runner
	}

	public func requestRepositoryRoot(at url: URL) async throws -> URL {
		do {
			let result = try await runner.requestRun(
				arguments: ["rev-parse", "--show-toplevel"],
				at: url
			)
			let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !path.isEmpty else { throw GitRepositoryError.invalidRepository }
			return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			throw GitRepositoryError.invalidRepository
		}
	}

	public func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] {
		let result = try await runner.requestRun(
			arguments: [
				"--no-optional-locks",
				"status",
				"--porcelain=v1",
				"-z",
				"--untracked-files=all",
			],
			at: repositoryURL
		)
		return GitOutputParser.parseWorkingTreeChanges(result.standardOutput)
	}

	public func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] {
		let format = "%H%x1f%h%x1f%P%x1f%an%x1f%aI%x1f%D%x1f%s%x1e"
		do {
			let result = try await runner.requestRun(
				arguments: ["log", "--all", "--topo-order", "-n", "500", "--pretty=format:\(format)"],
				at: repositoryURL
			)
			return GitOutputParser.parseCommits(result.standardOutput)
		} catch let error as GitRepositoryError {
			if error.errorDescription?.contains("does not have any commits yet") == true {
				return []
			}
			throw error
		}
	}

	public func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] {
		let format = "%(refname:short)\t%(objectname:short)\t%(HEAD)\t%(upstream:short)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"],
			at: repositoryURL
		)
		return GitOutputParser.parseBranches(result.standardOutput)
	}

	public func requestTags(at repositoryURL: URL) async throws -> [GitTag] {
		let format = "%(refname:short)\t%(objectname:short)\t%(creatordate:iso8601)\t%(subject)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"],
			at: repositoryURL
		)
		return GitOutputParser.parseTags(result.standardOutput)
	}

	public func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode] {
		let paths: [String]
		do {
			let result = try await runner.requestRun(
				arguments: ["ls-tree", "-r", "-z", "--name-only", "HEAD"],
				at: repositoryURL
			)
			paths = result.standardOutput.split(separator: "\0").map(String.init)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let result = try await runner.requestRun(
				arguments: ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
				at: repositoryURL
			)
			paths = result.standardOutput.split(separator: "\0").map(String.init)
		}
		return GitOutputParser.buildFileTree(paths: paths)
	}

	public func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data {
		let task = Task.detached(priority: .userInitiated) {
			try Task.checkCancellation()

			let rootURL = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
			let fileURL =
				repositoryURL
				.appending(path: path)
				.standardizedFileURL
				.resolvingSymlinksInPath()
			let rootPath = rootURL.path
			guard fileURL.path.hasPrefix(rootPath + "/") else {
				throw GitRepositoryError.invalidFilePath
			}

			let values: URLResourceValues
			do {
				values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
			} catch {
				throw GitRepositoryError.fileUnavailable
			}

			guard values.isRegularFile == true, let byteCount = values.fileSize else {
				throw GitRepositoryError.fileUnavailable
			}
			guard byteCount <= Self.maximumPreviewByteCount else {
				throw GitRepositoryError.fileTooLarge
			}

			do {
				let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
				try Task.checkCancellation()
				return data
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				throw GitRepositoryError.fileUnavailable
			}
		}

		return try await withTaskCancellationHandler {
			try await task.value
		} onCancel: {
			task.cancel()
		}
	}

	public func requestDiff(for change: WorkingTreeChange, at repositoryURL: URL) async throws
		-> String
	{
		if change.workingTreeState == .untracked {
			return try await runner.requestRun(
				arguments: ["diff", "--no-index", "--no-color", "--", "/dev/null", change.path],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 1]
			).standardOutput
		}

		if change.isStaged && !change.hasWorkingTreeChange {
			return try await runner.requestRun(
				arguments: ["diff", "--cached", "--no-color", "--", change.path],
				at: repositoryURL
			).standardOutput
		}

		return try await runner.requestRun(
			arguments: ["diff", "--no-color", "--", change.path],
			at: repositoryURL
		).standardOutput
	}

	public func requestStage(path: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["add", "--", path], at: repositoryURL)
	}

	public func requestUnstage(path: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["restore", "--staged", "--", path], at: repositoryURL)
	}

	public func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws {
		let diffArguments: [String]
		let applyArguments: [String]
		switch action {
		case .stage:
			diffArguments = ["diff", "--no-color", "--unified=0", "--", change.path]
			applyArguments = ["apply", "--cached", "--unidiff-zero", "--whitespace=nowarn", "-"]
		case .unstage:
			diffArguments = ["diff", "--cached", "--no-color", "--unified=0", "--", change.path]
			applyArguments = [
				"apply",
				"--cached",
				"--reverse",
				"--unidiff-zero",
				"--whitespace=nowarn",
				"-",
			]
		}

		let diff = try await runner.requestRun(
			arguments: diffArguments,
			at: repositoryURL
		).standardOutput
		let patch = try GitLinePatchBuilder.makePatch(from: diff, selection: selection)
		_ = try await runner.requestRun(
			arguments: applyArguments,
			at: repositoryURL,
			standardInput: patch
		)
	}

	public func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws {
		let affectedPaths = [change.path, change.previousPath].compactMap { $0 }

		if change.isStaged {
			_ = try await runner.requestRun(
				arguments: ["restore", "--staged", "--"] + affectedPaths,
				at: repositoryURL
			)
		}

		let trackedPathsResult = try await runner.requestRun(
			arguments: ["ls-files", "-z", "--"] + affectedPaths,
			at: repositoryURL
		)
		let trackedPaths = trackedPathsResult.standardOutput
			.split(separator: "\0")
			.map(String.init)
		let untrackedPaths = affectedPaths.filter { !trackedPaths.contains($0) }

		if !trackedPaths.isEmpty {
			_ = try await runner.requestRun(
				arguments: ["restore", "--worktree", "--"] + trackedPaths,
				at: repositoryURL
			)
		}

		if !untrackedPaths.isEmpty {
			_ = try await runner.requestRun(
				arguments: ["clean", "-f", "--"] + untrackedPaths,
				at: repositoryURL
			)
		}
	}

	public func requestCommit(message: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["commit", "-m", message], at: repositoryURL)
	}

	public func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["switch", name], at: repositoryURL)
	}

	public func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["switch", "-c", name], at: repositoryURL)
	}

	public func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["branch", "-d", name], at: repositoryURL)
	}

	public func requestCreateTag(
		named name: String,
		message: String,
		at repositoryURL: URL
	) async throws {
		let arguments = message.isEmpty ? ["tag", name] : ["tag", "-a", name, "-m", message]
		_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
	}

	public func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["tag", "-d", name], at: repositoryURL)
	}

	public func requestPull(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["pull", "--ff-only"], at: repositoryURL)
	}

	public func requestPush(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["push"], at: repositoryURL)
	}
}
