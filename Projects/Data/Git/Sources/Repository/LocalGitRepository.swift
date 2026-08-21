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
		return GitOutputParser.parseWorkingTreeChanges(result.standardOutput).map { change in
			guard
				change.indexState == .deleted,
				change.workingTreeState == .unchanged,
				FileManager.default.fileExists(
					atPath: repositoryURL.appending(path: change.path).path
				)
			else { return change }

			return WorkingTreeChange(
				path: change.path,
				previousPath: change.previousPath,
				indexState: change.indexState,
				workingTreeState: .untracked
			)
		}
	}

	public func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] {
		guard let base = try await requestAmendBase(at: repositoryURL) else { return [] }
		let result = try await runner.requestRun(
			arguments: [
				"diff",
				"--cached",
				"--name-status",
				"--find-renames",
				"-z",
				base,
				"--",
			],
			at: repositoryURL
		)
		return GitOutputParser.parseAmendChanges(result.standardOutput)
	}

	public func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] {
		let format = "%H%x1f%h%x1f%P%x1f%an%x1f%aI%x1f%D%x1f%s%x1f%b%x1e"
		do {
			let result = try await runner.requestRun(
				arguments: [
					"log",
					"--branches",
					"--remotes",
					"--tags",
					"--topo-order",
					"--pretty=format:\(format)",
				],
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

	public func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String
	{
		try await runner.requestRun(
			arguments: [
				"show",
				"--format=",
				"--no-color",
				"--find-renames",
				"--unified=3",
				commit.hash,
			],
			at: repositoryURL
		).standardOutput
	}

	public func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] {
		let format = "%(refname:short)\t%(objectname:short)\t%(HEAD)\t%(upstream:short)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"],
			at: repositoryURL
		)
		return GitOutputParser.parseBranches(result.standardOutput)
	}

	public func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote] {
		let remoteResult = try await runner.requestRun(
			arguments: ["remote", "-v"],
			at: repositoryURL
		)
		let branchFormat =
			"%(refname:short)\t%(objectname:short)\t%(objectname)\t%(symref)"
		let branchResult = try await runner.requestRun(
			arguments: [
				"for-each-ref",
				"--sort=-committerdate",
				"--format=\(branchFormat)",
				"refs/remotes",
			],
			at: repositoryURL
		)
		let branches = GitOutputParser.parseRemoteBranches(branchResult.standardOutput)

		return GitOutputParser.parseRemotes(remoteResult.standardOutput).map { remote in
			GitRemote(
				name: remote.name,
				fetchURL: remote.fetchURL,
				pushURL: remote.pushURL,
				branches: branches.filter { $0.remoteName == remote.name }
			)
		}
	}

	public func requestTags(at repositoryURL: URL) async throws -> [GitTag] {
		let format =
			"%(refname:short)\t%(objectname:short)\t%(*objectname)\t%(objectname)\t%(creatordate:iso8601)\t%(subject)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"],
			at: repositoryURL
		)
		return GitOutputParser.parseTags(result.standardOutput)
	}

	public func requestStashes(at repositoryURL: URL) async throws -> [GitStash] {
		let format = "%gd%x1f%H%x1f%gs%x1f%ci%x1e"
		let result = try await runner.requestRun(
			arguments: ["stash", "list", "--format=\(format)"],
			at: repositoryURL
		)
		return GitOutputParser.parseStashes(result.standardOutput)
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

	public func requestAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		guard let base = try await requestAmendBase(at: repositoryURL) else { return "" }
		let paths = [change.path, change.previousPath].compactMap { $0 }
		return try await runner.requestRun(
			arguments: ["diff", "--cached", "--no-color", "--find-renames", base, "--"] + paths,
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

	public func requestUnstageFromAmend(
		change: GitAmendChange,
		at repositoryURL: URL
	) async throws {
		guard let base = try await requestAmendBase(at: repositoryURL) else {
			throw GitRepositoryError.invalidOutput
		}
		let paths = [change.path, change.previousPath].compactMap { $0 }
		_ = try await runner.requestRun(
			arguments: ["reset", base, "--"] + paths,
			at: repositoryURL
		)
	}

	public func requestCommit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws {
		var arguments = ["commit"]
		if amend {
			arguments.append("--amend")
		}
		arguments.append(contentsOf: ["--file", "-"])
		let message = body.isEmpty ? subject : "\(subject)\n\n\(body)"
		_ = try await runner.requestRun(
			arguments: arguments,
			at: repositoryURL,
			standardInput: message
		)
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

	public func requestCreateStash(message: String, at repositoryURL: URL) async throws {
		var arguments = ["stash", "push", "--include-untracked"]
		if !message.isEmpty {
			arguments.append(contentsOf: ["--message", message])
		}
		_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
	}

	public func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["stash", "apply", "--index", stash.reference],
			at: repositoryURL
		)
	}

	public func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["stash", "pop", "--index", stash.reference],
			at: repositoryURL
		)
	}

	public func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["stash", "drop", stash.reference],
			at: repositoryURL
		)
	}

	public func requestPull(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["pull", "--ff-only"], at: repositoryURL)
	}

	public func requestPush(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["push"], at: repositoryURL)
	}

	private func requestAmendBase(at repositoryURL: URL) async throws -> String? {
		let head = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "--quiet", "HEAD"],
			at: repositoryURL,
			acceptedTerminationStatuses: [0, 1]
		)
		guard !head.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return nil
		}

		let parent = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "--quiet", "HEAD^"],
			at: repositoryURL,
			acceptedTerminationStatuses: [0, 1]
		)
		let parentHash = parent.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
		guard parentHash.isEmpty else { return parentHash }

		let emptyTree = try await runner.requestRun(
			arguments: ["hash-object", "-t", "tree", "-w", "--stdin"],
			at: repositoryURL,
			standardInput: ""
		)
		return emptyTree.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
