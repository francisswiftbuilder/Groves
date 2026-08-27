import DomainGitInterface
import Foundation

public struct LocalGitRepository: GitRepository {
	private static let maximumPreviewByteCount = 10 * 1_024 * 1_024
	private let runner: GitProcessRunner

	public init(configuration: GitProcessConfiguration = GitProcessConfiguration()) {
		runner = GitProcessRunner(configuration: configuration)
	}

	init(runner: GitProcessRunner) {
		self.runner = runner
	}

	private func diffOptionArguments(_ options: GitDiffOptions) -> [String] {
		var arguments = ["--unified=\(options.contextLineCount ?? 999_999)"]
		if options.ignoresWhitespace {
			arguments.append("--ignore-all-space")
		}
		return arguments
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

	public func requestCloneRepository(
		from remoteURL: String,
		into directoryURL: URL
	) async throws -> URL {
		let remoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let repositoryName = repositoryName(from: remoteURL) else {
			throw GitRepositoryError.invalidRemoteURL
		}

		let repositoryURL =
			directoryURL
			.appending(path: repositoryName, directoryHint: .isDirectory)
			.standardizedFileURL
		guard FileManager.default.fileExists(atPath: repositoryURL.path) == false else {
			throw GitRepositoryError.repositoryAlreadyExists
		}

		_ = try await runner.requestRun(
			arguments: ["clone", "--", remoteURL, repositoryURL.path],
			at: directoryURL,
			isNetworkOperation: true
		)
		return repositoryURL
	}

	public func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] {
		try await requestWorkingTreeChanges(paths: [], at: repositoryURL)
	}

	public func requestWorkingTreeChanges(
		relatedTo change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		let paths = [change.path, change.previousPath].compactMap { $0 }
		return try await requestWorkingTreeChanges(paths: paths, at: repositoryURL)
	}

	private func requestWorkingTreeChanges(
		paths: [String],
		at repositoryURL: URL
	) async throws -> [WorkingTreeChange] {
		var arguments = [
			"--no-optional-locks",
			"status",
			"--porcelain=v1",
			"-z",
			"--untracked-files=all",
		]
		if !paths.isEmpty {
			arguments.append("--")
			arguments.append(contentsOf: paths)
		}
		let result = try await runner.requestRun(
			arguments: arguments,
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

	private func repositoryName(from remoteURL: String) -> String? {
		guard remoteURL.isEmpty == false else { return nil }
		let trimmedURL = remoteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard
			let component = trimmedURL.split(whereSeparator: { $0 == "/" || $0 == ":" }).last
		else { return nil }

		var name = String(component)
		if name.hasSuffix(".git") {
			name.removeLast(4)
		}
		guard name.isEmpty == false, name != ".", name != ".." else { return nil }
		return name
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
		let format =
			"%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI%x1f%D%x1f%s%x1f%b%x1e"
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

	public func requestCommitDiff(
		for commit: GitCommit,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		return try await runner.requestRun(
			arguments: [
				"show",
				"--format=",
				"--diff-merges=first-parent",
				"--no-color",
				"--find-renames",
			] + diffOptionArguments(options) + [commit.hash],
			at: repositoryURL
		).standardOutput
	}

	public func requestStashDiff(
		for stash: GitStash,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		try await runner.requestRun(
			arguments: [
				"stash", "show", "--include-untracked", "--patch", "--no-color", "--find-renames",
			] + diffOptionArguments(options) + [stash.reference],
			at: repositoryURL
		).standardOutput
	}

	public func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] {
		let format =
			"%(refname:short)\t%(objectname:short)\t%(HEAD)\t%(upstream:short)\t%(upstream:track,nobracket)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"],
			at: repositoryURL
		)
		return GitOutputParser.parseBranches(result.standardOutput)
	}

	public func requestOperationState(at repositoryURL: URL) async throws
		-> RepositoryOperationState
	{
		async let statusResult = runner.requestRun(
			arguments: ["--no-optional-locks", "status", "--porcelain=v2", "--branch", "-z"],
			at: repositoryURL
		)
		async let markerResult = runner.requestRun(
			arguments: [
				"rev-parse",
				"--git-path",
				"MERGE_HEAD",
				"--git-path",
				"rebase-merge",
				"--git-path",
				"rebase-apply",
				"--git-path",
				"CHERRY_PICK_HEAD",
				"--git-path",
				"REVERT_HEAD",
			],
			at: repositoryURL
		)

		let results = try await (statusResult, markerResult)
		let statusRecords = results.0.standardOutput.split(separator: "\0").map(String.init)
		let conflicts = GitOutputParser.parseConflicts(results.0.standardOutput)

		let markerPaths = results.1.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
		guard markerPaths.count == 5 else { throw GitRepositoryError.invalidOutput }
		let markerExists = markerPaths.map { markerPath in
			FileManager.default.fileExists(atPath: resolvedGitPath(markerPath, at: repositoryURL).path)
		}

		let head: RepositoryHeadState =
			statusRecords.contains("# branch.head (detached)") ? .detached : .attached
		let operation: RepositoryOperation?
		if markerExists[0] {
			operation = RepositoryOperation(kind: .merge)
		} else if markerExists[1] || markerExists[2] {
			operation = RepositoryOperation(
				kind: .rebase,
				progress: requestRebaseProgress(
					at: markerExists[1]
						? resolvedGitPath(markerPaths[1], at: repositoryURL)
						: resolvedGitPath(markerPaths[2], at: repositoryURL)
				)
			)
		} else if markerExists[3] {
			operation = RepositoryOperation(kind: .cherryPick)
		} else if markerExists[4] {
			operation = RepositoryOperation(kind: .revert)
		} else {
			operation = nil
		}
		return RepositoryOperationState(head: head, operation: operation, conflicts: conflicts)
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

	public func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws
		-> String
	{
		if source == .unstaged, change.workingTreeState == .untracked {
			return try await runner.requestRun(
				arguments: ["diff", "--no-index", "--no-color"] + diffOptionArguments(options)
					+ ["--", "/dev/null", change.path],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 1]
			).standardOutput
		}

		if source == .staged {
			return try await runner.requestRun(
				arguments: ["diff", "--cached", "--no-color"] + diffOptionArguments(options)
					+ ["--", change.path],
				at: repositoryURL
			).standardOutput
		}

		return try await runner.requestRun(
			arguments: ["diff", "--no-color"] + diffOptionArguments(options) + ["--", change.path],
			at: repositoryURL
		).standardOutput
	}

	public func requestAmendDiff(
		for change: GitAmendChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws -> String {
		guard let base = try await requestAmendBase(at: repositoryURL) else { return "" }
		let paths = [change.path, change.previousPath].compactMap { $0 }
		return try await runner.requestRun(
			arguments: ["diff", "--cached", "--no-color", "--find-renames"]
				+ diffOptionArguments(options) + [base, "--"] + paths,
			at: repositoryURL
		).standardOutput
	}

	public func requestImageDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		let previousPath = change.previousPath ?? change.path
		switch source {
		case .staged:
			async let before = requestBlobData(
				revision: "HEAD",
				path: previousPath,
				at: repositoryURL
			)
			async let after = requestBlobData(
				revision: "",
				path: change.path,
				at: repositoryURL
			)
			return await GitImageDiff(before: before, after: after)
		case .unstaged:
			async let before = requestBlobData(
				revision: "",
				path: previousPath,
				at: repositoryURL
			)
			async let after = requestWorkingTreeData(path: change.path, at: repositoryURL)
			return await GitImageDiff(before: before, after: after)
		}
	}

	public func requestAmendImageDiff(
		for change: GitAmendChange,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		let base = try await requestAmendBase(at: repositoryURL)
		async let before = requestBlobData(
			revision: base,
			path: change.previousPath ?? change.path,
			at: repositoryURL
		)
		async let after = requestBlobData(
			revision: "",
			path: change.path,
			at: repositoryURL
		)
		return await GitImageDiff(before: before, after: after)
	}

	public func requestCommitImageDiff(
		for commit: GitCommit,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		async let before = requestBlobData(
			revision: commit.parentHashes.first,
			path: previousPath ?? path,
			at: repositoryURL
		)
		async let after = requestBlobData(
			revision: commit.hash,
			path: path,
			at: repositoryURL
		)
		return await GitImageDiff(before: before, after: after)
	}

	public func requestStashImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		async let before = requestBlobData(
			revision: "\(stash.reference)^1",
			path: previousPath ?? path,
			at: repositoryURL
		)
		let trackedAfter = await requestBlobData(
			revision: stash.reference,
			path: path,
			at: repositoryURL
		)
		let after: Data?
		if let trackedAfter {
			after = trackedAfter
		} else {
			after = await requestBlobData(
				revision: "\(stash.reference)^3",
				path: path,
				at: repositoryURL
			)
		}
		return await GitImageDiff(before: before, after: after)
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

	public func requestApplyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws {
		let diffArguments: [String]
		let applyArguments: [String]
		switch action {
		case .stage:
			diffArguments =
				["diff", "--no-color"] + diffOptionArguments(options)
				+ ["--", change.path]
			applyArguments = ["apply", "--cached", "--whitespace=nowarn", "-"]
		case .unstage:
			diffArguments =
				["diff", "--cached", "--no-color"] + diffOptionArguments(options)
				+ ["--", change.path]
			applyArguments = ["apply", "--cached", "--reverse", "--whitespace=nowarn", "-"]
		case .discard:
			diffArguments =
				["diff", "--no-color"] + diffOptionArguments(options)
				+ ["--", change.path]
			applyArguments = ["apply", "--reverse", "--whitespace=nowarn", "-"]
		}

		let diff = try await runner.requestRun(
			arguments: diffArguments,
			at: repositoryURL
		).standardOutput
		let patch = try GitHunkPatchBuilder.makePatch(from: diff, selection: selection)
		_ = try await runner.requestRun(
			arguments: applyArguments,
			at: repositoryURL,
			standardInput: patch
		)
	}

	public func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws {
		let affectedPaths = [change.path, change.previousPath].compactMap { $0 }

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

	public func requestAmendWithoutEditingMessage(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["commit", "--amend", "--no-edit"],
			at: repositoryURL,
			environment: operationEnvironment
		)
	}

	public func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(arguments: ["switch", name], at: repositoryURL)
	}

	public func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(arguments: ["switch", "-c", name], at: repositoryURL)
	}

	public func requestCreateBranch(
		named name: String,
		from commitHash: String,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["switch", "-c", name, commitHash],
			at: repositoryURL
		)
	}

	public func requestCheckoutCommit(_ commitHash: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		guard try await requestWorkingTreeChanges(at: repositoryURL).isEmpty else {
			throw GitRepositoryError.commandFailed(
				"변경 사항을 먼저 commit하거나 stash한 뒤 commit을 checkout해 주세요."
			)
		}
		_ = try await runner.requestRun(
			arguments: ["switch", "--detach", commitHash],
			at: repositoryURL
		)
	}

	public func requestCreateTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["switch", "--track", "-c", name, remoteBranch],
			at: repositoryURL
		)
	}

	public func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(arguments: ["branch", "-d", name], at: repositoryURL)
	}

	public func requestRenameBranch(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(arguments: ["branch", "-m", name, newName], at: repositoryURL)
	}

	public func requestMergeBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		do {
			_ = try await runner.requestRun(
				arguments: ["merge", "--no-edit", "--", name],
				at: repositoryURL
			)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let operationState = try? await requestOperationState(at: repositoryURL)
			guard operationState?.operation?.kind == .merge || operationState?.hasConflicts == true else {
				throw error
			}
		}
	}

	public func requestRebase(onto branchName: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		try await requestOperationStart(
			arguments: ["rebase", branchName],
			expectedOperation: .rebase,
			at: repositoryURL
		)
	}

	public func requestCherryPick(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		var arguments = ["cherry-pick"]
		if let mainline {
			arguments.append(contentsOf: ["--mainline", String(mainline)])
		}
		arguments.append(commitHash)
		try await requestOperationStart(
			arguments: arguments,
			expectedOperation: .cherryPick,
			at: repositoryURL
		)
	}

	public func requestRevert(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		var arguments = ["revert", "--no-edit"]
		if let mainline {
			arguments.append(contentsOf: ["--mainline", String(mainline)])
		}
		arguments.append(commitHash)
		try await requestOperationStart(
			arguments: arguments,
			expectedOperation: .revert,
			at: repositoryURL
		)
	}

	public func requestResolveConflict(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		at repositoryURL: URL
	) async throws {
		let hasSelectedStage = resolution == .ours ? conflict.hasOurs : conflict.hasTheirs
		if hasSelectedStage {
			let option = resolution == .ours ? "--ours" : "--theirs"
			_ = try await runner.requestRun(
				arguments: ["checkout", option, "--", conflict.path],
				at: repositoryURL
			)
		} else {
			_ = try await runner.requestRun(
				arguments: ["rm", "-f", "--", conflict.path],
				at: repositoryURL
			)
		}
		try await requestMarkConflictResolved(path: conflict.path, at: repositoryURL)
	}

	public func requestConflictContent(
		for conflict: GitConflict,
		at repositoryURL: URL
	) async throws -> GitConflictContent {
		async let baseData = requestConflictStageData(
			1,
			exists: conflict.hasBase,
			path: conflict.path,
			at: repositoryURL
		)
		async let currentData = requestConflictStageData(
			2,
			exists: conflict.hasOurs,
			path: conflict.path,
			at: repositoryURL
		)
		async let incomingData = requestConflictStageData(
			3,
			exists: conflict.hasTheirs,
			path: conflict.path,
			at: repositoryURL
		)
		let workingTreeData = try? await requestFileContents(
			at: conflict.path,
			in: repositoryURL
		)
		let stageContents = await (baseData, currentData, incomingData)
		let base = stageContents.0.flatMap { String(data: $0, encoding: .utf8) }
		let current = stageContents.1.flatMap { String(data: $0, encoding: .utf8) }
		let incoming = stageContents.2.flatMap { String(data: $0, encoding: .utf8) }
		let workingTree = workingTreeData.flatMap { String(data: $0, encoding: .utf8) }
		return GitConflictContent(
			base: base,
			current: current,
			incoming: incoming,
			workingTree: workingTree,
			hunks: workingTree.map(GitConflictMarkerParser.parse) ?? [],
			baseData: stageContents.0,
			currentData: stageContents.1,
			incomingData: stageContents.2,
			workingTreeData: workingTreeData
		)
	}

	public func requestResolveConflictHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution,
		at repositoryURL: URL
	) async throws {
		let data = try await requestFileContents(at: conflict.path, in: repositoryURL)
		guard let contents = String(data: data, encoding: .utf8) else {
			throw GitRepositoryError.invalidOutput
		}
		let resolvedContents = try GitConflictMarkerParser.resolve(
			hunk.index,
			using: resolution,
			in: contents
		)
		let rootURL = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
		let fileURL = repositoryURL.appending(path: conflict.path).standardizedFileURL
		guard fileURL.path.hasPrefix(rootURL.path + "/") else {
			throw GitRepositoryError.invalidFilePath
		}
		try Data(resolvedContents.utf8).write(to: fileURL, options: .atomic)
	}

	public func requestMarkConflictResolved(path: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["add", "-A", "--", path], at: repositoryURL)
	}

	private func requestConflictStageData(
		_ stage: Int,
		exists: Bool,
		path: String,
		at repositoryURL: URL
	) async -> Data? {
		guard exists else { return nil }
		return await requestBlobData(
			revision: ":\(stage)",
			path: path,
			at: repositoryURL
		)
	}

	public func requestPerformOperationAction(
		_ action: RepositoryOperationAction,
		for operation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws {
		let command: String
		switch operation {
		case .merge:
			command = "merge"
		case .rebase:
			command = "rebase"
		case .cherryPick:
			command = "cherry-pick"
		case .revert:
			command = "revert"
		}
		let option: String
		switch action {
		case .continue:
			option = "--continue"
		case .skip:
			guard operation != .merge else {
				throw GitRepositoryError.commandFailed("Merge cannot skip a commit.")
			}
			option = "--skip"
		case .abort:
			option = "--abort"
		}
		do {
			_ = try await runner.requestRun(
				arguments: [command, option],
				at: repositoryURL,
				environment: operationEnvironment
			)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let state = try? await requestOperationState(at: repositoryURL)
			guard action != .abort, state?.operation?.kind == operation || state?.hasConflicts == true
			else {
				throw error
			}
		}
	}

	public func requestReset(
		to commitHash: String,
		mode: GitResetMode,
		at repositoryURL: URL
	) async throws {
		let state = try await requestOperationState(at: repositoryURL)
		guard state.isIdle, !state.isDetached else {
			throw GitRepositoryError.commandFailed(
				"Reset is unavailable while HEAD is detached or an operation is in progress."
			)
		}
		_ = try await runner.requestRun(
			arguments: ["reset", "--\(mode.rawValue)", commitHash],
			at: repositoryURL
		)
	}

	public func requestCreateTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws {
		let arguments =
			message.isEmpty
			? ["tag", name, commitHash]
			: ["tag", "-a", name, "-m", message, commitHash]
		_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
	}

	public func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["tag", "-d", "--", name], at: repositoryURL)
	}

	public func requestCreateStash(
		message: String,
		includeUntracked: Bool = true,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		var arguments = ["stash", "push"]
		if includeUntracked {
			arguments.append("--include-untracked")
		}
		if !message.isEmpty {
			arguments.append(contentsOf: ["--message", message])
		}
		_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
	}

	public func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		try await requestStashMutation(
			arguments: ["stash", "apply", "--index", stash.reference],
			at: repositoryURL
		)
	}

	public func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		try await requestStashMutation(
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

	public func requestFetch(remote name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["fetch", name],
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	public func requestFetchAll(at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["fetch", "--all"],
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	public func requestPreparePull(at repositoryURL: URL) async throws -> RepositoryPullOutcome {
		try await requestEnsureIdle(at: repositoryURL)
		guard
			let currentBranch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
			let upstream = currentBranch.upstream,
			let remoteName = upstream.split(separator: "/", maxSplits: 1).first.map(String.init)
		else {
			throw GitRepositoryError.commandFailed(
				"현재 브랜치에 upstream이 없습니다. 먼저 upstream을 설정해 주세요."
			)
		}

		try await requestFetch(remote: remoteName, at: repositoryURL)
		guard let updatedBranch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent)
		else {
			throw GitRepositoryError.invalidOutput
		}

		switch (updatedBranch.aheadCount, updatedBranch.behindCount) {
		case (0, 0):
			return .upToDate
		case (let aheadCount, 0):
			return .aheadOnly(aheadCount: aheadCount)
		case (0, _):
			_ = try await runner.requestRun(
				arguments: ["merge", "--ff-only", "--", upstream],
				at: repositoryURL
			)
			return .fastForwarded
		case (let aheadCount, let behindCount):
			return .diverged(
				RepositoryPullDivergence(
					upstream: upstream,
					aheadCount: aheadCount,
					behindCount: behindCount
				)
			)
		}
	}

	public func requestResolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		guard try await requestWorkingTreeChanges(at: repositoryURL).isEmpty else {
			throw GitRepositoryError.commandFailed(
				"변경 사항을 먼저 commit하거나 stash한 뒤 pull을 계속해 주세요."
			)
		}
		switch resolution {
		case .rebase:
			try await requestRebase(onto: divergence.upstream, at: repositoryURL)
		case .merge:
			try await requestMergeBranch(named: divergence.upstream, at: repositoryURL)
		}
	}

	public func requestPush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: pushArguments(for: target),
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	public func requestForcePush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		var arguments = pushArguments(for: target)
		arguments.insert("--force-with-lease", at: 1)
		_ = try await runner.requestRun(
			arguments: arguments,
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	public func requestPushTags(remote name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["push", name, "--tags"],
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	public func requestAddRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {
		_ = try await runner.requestRun(
			arguments: ["remote", "add", name, fetchURL], at: repositoryURL)
		try await requestSetPushURL(pushURL, for: name, at: repositoryURL)
	}

	public func requestRenameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws {
		_ = try await runner.requestRun(
			arguments: ["remote", "rename", name, newName], at: repositoryURL)
	}

	public func requestUpdateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {
		_ = try await runner.requestRun(
			arguments: ["remote", "set-url", name, fetchURL], at: repositoryURL)
		try await requestSetPushURL(pushURL, for: name, at: repositoryURL)
	}

	public func requestDeleteRemote(named name: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(arguments: ["remote", "remove", name], at: repositoryURL)
	}

	public func requestDeleteRemoteBranch(
		_ branch: GitRemoteBranch,
		at repositoryURL: URL
	) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["push", branch.remoteName, "--delete", branch.name],
			at: repositoryURL,
			isNetworkOperation: true
		)
	}

	private func pushArguments(for target: GitPushTarget) -> [String] {
		let arguments: [String]
		switch target {
		case .upstream:
			arguments = ["push"]
		case .setUpstream(let remoteName, let branchName):
			arguments = ["push", "--set-upstream", remoteName, branchName]
		}
		return arguments
	}

	private func resolvedGitPath(_ path: String, at repositoryURL: URL) -> URL {
		if path.hasPrefix("/") {
			return URL(fileURLWithPath: path)
		}
		return repositoryURL.appending(path: path)
	}

	private var operationEnvironment: [String: String] {
		[
			"GIT_EDITOR": "true",
			"GIT_SEQUENCE_EDITOR": "true",
			"GIT_MERGE_AUTOEDIT": "no",
		]
	}

	private func requestOperationStart(
		arguments: [String],
		expectedOperation: RepositoryOperationKind,
		at repositoryURL: URL
	) async throws {
		do {
			_ = try await runner.requestRun(
				arguments: arguments,
				at: repositoryURL,
				environment: operationEnvironment
			)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let state = try? await requestOperationState(at: repositoryURL)
			guard state?.operation?.kind == expectedOperation || state?.hasConflicts == true else {
				throw error
			}
		}
	}

	private func requestStashMutation(arguments: [String], at repositoryURL: URL) async throws {
		do {
			_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let state = try? await requestOperationState(at: repositoryURL)
			guard state?.hasConflicts == true else { throw error }
		}
	}

	private func requestSetPushURL(
		_ pushURL: String?,
		for remoteName: String,
		at repositoryURL: URL
	) async throws {
		if let pushURL, !pushURL.isEmpty {
			_ = try await runner.requestRun(
				arguments: ["remote", "set-url", "--push", remoteName, pushURL],
				at: repositoryURL
			)
		} else {
			_ = try await runner.requestRun(
				arguments: ["config", "--unset-all", "remote.\(remoteName).pushurl"],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 5]
			)
		}
	}

	private func requestEnsureIdle(at repositoryURL: URL) async throws {
		let state = try await requestOperationState(at: repositoryURL)
		guard state.isIdle else {
			throw GitRepositoryError.commandFailed(
				"Finish or abort the current Git operation before starting another action."
			)
		}
	}

	private func requestRebaseProgress(at directoryURL: URL) -> RepositoryOperationProgress? {
		let candidates = [("msgnum", "end"), ("next", "last")]
		for candidate in candidates {
			let currentURL = directoryURL.appending(path: candidate.0)
			let totalURL = directoryURL.appending(path: candidate.1)
			guard
				let currentValue = try? String(contentsOf: currentURL, encoding: .utf8),
				let totalValue = try? String(contentsOf: totalURL, encoding: .utf8),
				let current = Int(currentValue.trimmingCharacters(in: .whitespacesAndNewlines)),
				let total = Int(totalValue.trimmingCharacters(in: .whitespacesAndNewlines))
			else { continue }
			return RepositoryOperationProgress(current: current, total: total)
		}
		return nil
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

	private func requestBlobData(
		revision: String?,
		path: String,
		at repositoryURL: URL
	) async -> Data? {
		guard let revision else { return nil }
		let object = revision.isEmpty ? ":\(path)" : "\(revision):\(path)"
		guard
			let result = try? await runner.requestRun(
				arguments: ["show", object],
				at: repositoryURL
			)
		else { return nil }
		guard result.standardOutputData.count <= Self.maximumPreviewByteCount else { return nil }
		return result.standardOutputData
	}

	private func requestWorkingTreeData(path: String, at repositoryURL: URL) async -> Data? {
		try? await requestFileContents(at: path, in: repositoryURL)
	}
}
