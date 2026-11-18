import DomainGitInterface
import Foundation

public struct LocalGitRepository: GitCommitPlanningRepository, GitRepository {
	private static let maximumPreviewByteCount = 10 * 1_024 * 1_024
	private let runner: GitProcessRunner
	private let archiveDiscardedFiles: @Sendable (URL) throws -> Void

	public init(configuration: GitProcessConfiguration = GitProcessConfiguration()) {
		self.init(runner: GitProcessRunner(configuration: configuration))
	}

	init(
		runner: GitProcessRunner,
		archiveDiscardedFiles: @escaping @Sendable (URL) throws -> Void = {
			try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
		}
	) {
		self.runner = runner
		self.archiveDiscardedFiles = archiveDiscardedFiles
	}

	private func diffOptionArguments(_ options: GitDiffOptions) -> [String] {
		var arguments = [
			"--no-ext-diff", "--no-textconv", "--unified=\(options.contextLineCount ?? 999_999)",
		]
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
		guard let repositoryName = repositoryName(from: remoteURL),
			GitRemoteURLValidator.containsEmbeddedCredential(remoteURL) == false
		else {
			throw GitRepositoryError.invalidRemoteURL
		}
		let resolvedRemote = try await runner.requestRun(
			arguments: ["ls-remote", "--get-url", "--", remoteURL], at: directoryURL
		).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !GitRemoteURLValidator.containsEmbeddedCredential(resolvedRemote) else {
			throw GitRepositoryError.invalidRemoteURL
		}

		let repositoryURL =
			directoryURL
			.appending(path: repositoryName, directoryHint: .isDirectory)
			.standardizedFileURL
		guard FileManager.default.fileExists(atPath: repositoryURL.path) == false else {
			throw GitRepositoryError.repositoryAlreadyExists
		}
		let stagingURL = directoryURL.appending(
			path: ".groves-clone-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: stagingURL) }
		_ = try await runner.requestRun(
			arguments: ["clone", "--", remoteURL, stagingURL.path],
			at: directoryURL,
			isNetworkOperation: true,
			requiresSSHTrustScope: GitRemoteURLValidator.isSSHRemote(resolvedRemote)
		)
		try Task.checkCancellation()
		do {
			try FileManager.default.moveItem(at: stagingURL, to: repositoryURL)
		} catch let error as CocoaError where error.code == .fileWriteFileExists {
			throw GitRepositoryError.repositoryAlreadyExists
		}
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
			"--literal-pathspecs", "status",
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
			at: repositoryURL,
			environment: ["GIT_OPTIONAL_LOCKS": "0"]
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
		let head = try await requestCommitPlanHead(at: repositoryURL)
		do {
			let result = try await runner.requestRun(
				arguments: [
					"log",
					"--no-show-signature",
					"--no-notes",
					"--branches",
					"--remotes",
					"--tags",
					"--topo-order",
					"--pretty=format:\(format)",
				] + [head].compactMap { $0 } + ["--"],
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
				"--no-show-signature",
				"--no-notes",
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
		let hash = try await requestStashHash(stash.hash, at: repositoryURL)
		return try await runner.requestRun(
			arguments: [
				"stash", "show", "--include-untracked", "--patch", "--no-color", "--find-renames",
			] + diffOptionArguments(options) + ["--", hash],
			at: repositoryURL
		).standardOutput
	}

	public func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] {
		let format =
			"%(refname:lstrip=2)\t%(objectname:short)\t%(HEAD)\t%(upstream:lstrip=2)\t"
			+ "%(upstream:track,nobracket)\t%(objectname)\t%(push:remotename)\t"
			+ "%(upstream:remotename)\t%(upstream:remoteref)\t%(upstream)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"],
			at: repositoryURL
		)
		var trackingReference: Substring?
		for record in result.standardOutput.split(whereSeparator: \.isNewline) {
			let fields = record.split(separator: "\t", omittingEmptySubsequences: false)
			if fields.count == 10, fields[2] == "*" {
				trackingReference = fields[9]
				break
			}
		}
		var customUpstreamHash: String?
		if let trackingReference, trackingReference.hasPrefix("refs/"),
			!trackingReference.hasPrefix("refs/remotes/")
		{
			let tracking = try await runner.requestRun(
				arguments: ["rev-parse", "--verify", "--quiet", "\(trackingReference)^{commit}"],
				at: repositoryURL, acceptedTerminationStatuses: [0, 1])
			let hash = tracking.standardOutput.trimmingCharacters(in: .newlines)
			if !hash.isEmpty { customUpstreamHash = hash }
		}
		return GitOutputParser.parseBranches(
			result.standardOutput, currentCustomUpstreamHash: customUpstreamHash)
	}

	public func requestOperationState(at repositoryURL: URL) async throws
		-> RepositoryOperationState
	{
		async let statusResult = runner.requestRun(
			arguments: ["status", "--porcelain=v2", "--branch", "-z"],
			at: repositoryURL,
			environment: ["GIT_OPTIONAL_LOCKS": "0"]
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
		let remotes = try await requestRemoteConfiguration(at: repositoryURL)
		let branchFormat =
			"%(refname)\t%(objectname:short)\t%(objectname)\t%(symref)"
		let branchResult = try await runner.requestRun(
			arguments: [
				"for-each-ref",
				"--sort=-committerdate",
				"--format=\(branchFormat)",
				"refs/remotes",
			],
			at: repositoryURL
		)
		let branches = GitOutputParser.parseRemoteBranches(
			branchResult.standardOutput, remoteNames: remotes.map(\.name))

		var result: [GitRemote] = []
		for remote in remotes {
			let urls = try await requestRemoteURLs(
				named: remote.name, usesPushURL: true, at: repositoryURL)
			let safeURLs =
				urls.contains(where: GitRemoteURLValidator.containsEmbeddedCredential) ? [] : urls
			let remoteBranches = branches.filter { $0.remoteName == remote.name }.map { branch in
				GitRemoteBranch(
					name: branch.name, fullName: branch.fullName, remoteName: branch.remoteName,
					shortHash: branch.shortHash, hash: branch.hash, pushURLs: safeURLs)
			}
			result.append(
				GitRemote(
					name: remote.name,
					fetchURLs: remote.fetchURLs,
					pushURLs: remote.pushURLs,
					branches: remoteBranches,
					effectivePushURLs: safeURLs))
		}
		return result
	}

	public func requestTags(at repositoryURL: URL) async throws -> [GitTag] {
		let format =
			"%(refname:lstrip=2)\t%(objectname:short)\t%(*objectname)\t%(objectname)\t%(creatordate:iso8601)\t%(subject)"
		let result = try await runner.requestRun(
			arguments: ["for-each-ref", "--sort=-creatordate", "--format=\(format)", "refs/tags"],
			at: repositoryURL
		)
		return GitOutputParser.parseTags(result.standardOutput)
	}

	public func requestStashes(at repositoryURL: URL) async throws -> [GitStash] {
		let format = "%gd%x1f%H%x1f%gs%x1f%ci%x1e"
		let result = try await runner.requestRun(
			arguments: ["stash", "list", "--no-show-signature", "--no-notes", "--format=\(format)"],
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
				let data = try Data(contentsOf: fileURL)
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
				arguments: ["--literal-pathspecs", "diff", "--no-index", "--no-color"]
					+ diffOptionArguments(options)
					+ ["--", "/dev/null", change.path],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 1]
			).standardOutput
		}

		if source == .staged {
			let paths = [change.path, change.previousPath].compactMap { $0 }
			return try await runner.requestRun(
				arguments: ["--literal-pathspecs", "diff", "--cached", "--no-color", "--find-renames"]
					+ diffOptionArguments(options)
					+ ["--"] + paths,
				at: repositoryURL
			).standardOutput
		}

		return try await runner.requestRun(
			arguments: ["--literal-pathspecs", "diff", "--no-color"] + diffOptionArguments(options) + [
				"--", change.path,
			],
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
			arguments: ["--literal-pathspecs", "diff", "--cached", "--no-color", "--find-renames"]
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
			return try await GitImageDiff(before: before, after: after)
		case .unstaged:
			async let before = requestBlobData(
				revision: "",
				path: previousPath,
				at: repositoryURL
			)
			async let after = requestWorkingTreeData(path: change.path, at: repositoryURL)
			return try await GitImageDiff(before: before, after: after)
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
		return try await GitImageDiff(before: before, after: after)
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
		return try await GitImageDiff(before: before, after: after)
	}

	public func requestStashImageDiff(
		for stash: GitStash,
		path: String,
		previousPath: String?,
		at repositoryURL: URL
	) async throws -> GitImageDiff {
		let hash = try await requestStashHash(stash.hash, at: repositoryURL)
		async let before = requestBlobData(
			revision: "\(hash)^1",
			path: previousPath ?? path,
			at: repositoryURL
		)
		let trackedAfter = try await requestBlobData(
			revision: hash,
			path: path,
			at: repositoryURL
		)
		let after: Data?
		if let trackedAfter {
			after = trackedAfter
		} else {
			after = try await requestBlobData(
				revision: "\(hash)^3",
				path: path,
				at: repositoryURL
			)
		}
		return try await GitImageDiff(before: before, after: after)
	}

	public func requestStage(path: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			_ = try await runner.requestRun(
				arguments: ["--literal-pathspecs", "add", "--", path], at: repositoryURL)
		}
	}

	public func requestUnstage(change: WorkingTreeChange, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			let paths = [change.path, change.previousPath].compactMap { $0 }
			let hasHead = try await requestCommitPlanHead(at: repositoryURL) != nil
			let arguments =
				hasHead
				? ["--literal-pathspecs", "restore", "--staged", "--"]
				: ["--literal-pathspecs", "rm", "--cached", "--force", "--ignore-unmatch", "--"]
			_ = try await runner.requestRun(
				arguments: arguments + paths, at: repositoryURL)
		}
	}

	public func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		expecting expectedDiff: String,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			let applyArguments: [String]
			switch action {
			case .stage:
				applyArguments = ["apply", "--cached", "--unidiff-zero", "--whitespace=nowarn", "-"]
			case .unstage:
				applyArguments = [
					"apply",
					"--cached",
					"--reverse",
					"--unidiff-zero",
					"--whitespace=nowarn",
					"-",
				]
			}

			try await requestValidateDiff(
				expectedDiff, for: change, source: action == .stage ? .unstaged : .staged,
				options: options, at: repositoryURL)
			let patch = try GitLinePatchBuilder.makePatch(from: expectedDiff, selection: selection)
			_ = try await runner.requestRun(
				arguments: applyArguments,
				at: repositoryURL,
				standardInput: patch
			)
		}
	}

	public func requestApplyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction,
		for change: WorkingTreeChange,
		expecting expectedDiff: String,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			let applyArguments: [String]
			switch action {
			case .stage:
				applyArguments = ["apply", "--cached", "--whitespace=nowarn", "-"]
			case .unstage:
				applyArguments = ["apply", "--cached", "--reverse", "--whitespace=nowarn", "-"]
			case .discard:
				applyArguments = ["apply", "--reverse", "--whitespace=nowarn", "-"]
			}

			try await requestValidateDiff(
				expectedDiff, for: change, source: action == .unstage ? .staged : .unstaged,
				options: options, at: repositoryURL)
			let patch = try GitHunkPatchBuilder.makePatch(from: expectedDiff, selection: selection)
			_ = try await runner.requestRun(
				arguments: applyArguments,
				at: repositoryURL,
				standardInput: patch
			)
		}
	}

	public func requestDiscardContext(for changes: [WorkingTreeChange], at repositoryURL: URL)
		async throws -> GitDiscardContext
	{
		let currentChanges = Set(try await requestWorkingTreeChanges(at: repositoryURL))
		guard !changes.isEmpty, changes.allSatisfy(currentChanges.contains) else {
			throw GitRepositoryError.commandFailed(
				"The selected files have changed. Review their changes before discarding.")
		}
		let paths = discardPaths(for: changes)
		let root = try await requestRepositoryRoot(at: repositoryURL).resolvingSymlinksInPath()
		let metadata = try await discardMetadata(for: paths, at: root)
		let files = try await discardFileFingerprint(for: paths, in: root, at: root)
		return GitDiscardContext(changes: changes, fingerprint: metadata + files)
	}

	private func discardMetadata(for paths: [String], at repositoryURL: URL) async throws -> [String]
	{
		let branch = try await requestCommitPlanBranchReference(at: repositoryURL)
		let head = try await requestCommitPlanHead(at: repositoryURL)
		let index = try await runner.requestRun(
			arguments: ["--literal-pathspecs", "ls-files", "--stage", "-z", "--"] + paths,
			at: repositoryURL
		).standardOutput
		return [repositoryURL.path, branch ?? "", head ?? "", index]
	}

	private func discardFileFingerprint(for paths: [String], in directory: URL, at repositoryURL: URL)
		async throws -> [String]
	{
		var fingerprint: [String] = []
		var regularPaths: [String] = []
		let manager = FileManager.default
		for path in paths {
			try Task.checkCancellation()
			let fileURL = directory.appending(path: path)
			let attributes: [FileAttributeKey: Any]
			do {
				attributes = try manager.attributesOfItem(atPath: fileURL.path)
			} catch let error as CocoaError
				where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
			{
				fingerprint.append("missing")
				continue
			}
			switch attributes[.type] as? FileAttributeType {
			case .typeRegular:
				regularPaths.append(fileURL.path)
				fingerprint.append("file \(attributes[.posixPermissions] as? Int ?? 0)")
			case .typeSymbolicLink:
				let target = try manager.destinationOfSymbolicLink(atPath: fileURL.path)
				fingerprint.append("link \(target)")
			default:
				throw GitRepositoryError.commandFailed("Only individual files can be discarded.")
			}
		}
		for start in stride(from: 0, to: regularPaths.count, by: 100) {
			let batch = regularPaths[start..<min(start + 100, regularPaths.count)]
			let hashes = try await runner.requestRun(
				arguments: ["hash-object", "--no-filters", "--"] + batch, at: repositoryURL
			).standardOutput
			fingerprint.append(hashes)
		}
		return fingerprint
	}

	public func requestDiscard(_ context: GitDiscardContext, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			let affectedPaths = discardPaths(for: context.changes)
			guard !affectedPaths.isEmpty else { return }
			let root = try await requestRepositoryRoot(at: repositoryURL).resolvingSymlinksInPath()
			let metadata = try await discardMetadata(for: affectedPaths, at: root)
			let changed = GitRepositoryError.commandFailed(
				"The selected files have changed. Review their changes before discarding.")
			guard context.fingerprint.starts(with: metadata) else { throw changed }
			let gitDirectoryPath = try await runner.requestRun(
				arguments: ["rev-parse", "--absolute-git-dir"], at: root
			).standardOutput.trimmingCharacters(in: .newlines)
			let transaction = try GitDiscardTransaction(
				repositoryURL: root, gitDirectory: URL(fileURLWithPath: gitDirectoryPath, isDirectory: true)
			)
			let selectedPaths = Set(affectedPaths)
			let trackedPaths = try await runner.requestRun(
				arguments: ["--literal-pathspecs", "ls-files", "-z", "--"] + affectedPaths, at: root
			).standardOutput.split(separator: "\0").map(String.init).filter(selectedPaths.contains)
			if !trackedPaths.isEmpty {
				_ = try await runner.requestRun(
					arguments: [
						"checkout-index", "--prefix=\(transaction.replacementsURL.path)/", "-z", "--stdin",
					],
					at: root, standardInput: trackedPaths.joined(separator: "\0") + "\0"
				)
			}
			do {
				for path in affectedPaths {
					try Task.checkCancellation()
					try transaction.capture(path: path)
				}
				let files = try await discardFileFingerprint(
					for: affectedPaths, in: transaction.originalsURL, at: root)
				guard metadata + files == context.fingerprint,
					try await discardMetadata(for: affectedPaths, at: root) == metadata
				else { throw changed }
				try Task.checkCancellation()
				for path in trackedPaths {
					try transaction.installReplacement(for: path)
				}
			} catch {
				guard transaction.rollback() else {
					throw GitRepositoryError.commandFailed(
						"Discard was interrupted. The remaining original files are in \(transaction.originalsURL.path).\n\n\(error.localizedDescription)"
					)
				}
				throw error
			}
			do {
				try transaction.archiveOriginals(using: archiveDiscardedFiles)
			} catch {
				throw GitRepositoryError.commandFailed(
					"Changes were discarded. The original files are in \(transaction.originalsURL.path).\n\n\(error.localizedDescription)"
				)
			}
		}
	}

	private func requestIndexURL(at repositoryURL: URL) async throws -> URL {
		let path = try await runner.requestRun(
			arguments: ["rev-parse", "--path-format=absolute", "--git-path", "index"], at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		return URL(fileURLWithPath: path)
	}

	private func makeDiscardTransaction(at root: URL) async throws -> GitDiscardTransaction {
		let path = try await runner.requestRun(
			arguments: ["rev-parse", "--absolute-git-dir"], at: root
		).standardOutput.trimmingCharacters(in: .newlines)
		return try GitDiscardTransaction(
			repositoryURL: root, gitDirectory: URL(fileURLWithPath: path, isDirectory: true))
	}

	private func discardRollbackError(_ transaction: GitDiscardTransaction, cause: any Error)
		-> any Error
	{
		if transaction.rollback() { return cause }
		return GitRepositoryError.commandFailed(
			"The operation was interrupted. The original files are in \(transaction.originalsURL.path).\n\n\(cause.localizedDescription)"
		)
	}

	private func archiveOriginals(in transaction: GitDiscardTransaction) throws {
		do {
			try transaction.archiveOriginals(using: archiveDiscardedFiles)
		} catch {
			throw GitRepositoryError.commandFailed(
				"The operation finished. The original files are in \(transaction.originalsURL.path).\n\n\(error.localizedDescription)"
			)
		}
	}

	private func changedConflict() -> GitRepositoryError {
		.commandFailed("The conflict has changed. Review the current file before resolving it.")
	}

	private func conflictWorkingTreeData(path: String, in directory: URL) throws -> Data? {
		let root = directory.resolvingSymlinksInPath().standardizedFileURL
		let url = root.appending(path: path).standardizedFileURL
		let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
		guard url.path.hasPrefix(root.path + "/"),
			parent.path == root.path || parent.path.hasPrefix(root.path + "/")
		else { throw GitRepositoryError.invalidFilePath }
		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
			switch attributes[.type] as? FileAttributeType {
			case .typeRegular:
				guard (attributes[.size] as? Int ?? 0) <= Self.maximumPreviewByteCount else {
					throw GitRepositoryError.fileTooLarge
				}
				let data = try Data(contentsOf: url)
				guard data.count <= Self.maximumPreviewByteCount else {
					throw GitRepositoryError.fileTooLarge
				}
				return data
			case .typeSymbolicLink:
				return try Data(FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8)
			default:
				throw GitRepositoryError.invalidFilePath
			}
		} catch let error as CocoaError
			where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
		{
			return nil
		}
	}

	private func discardPaths(for changes: [WorkingTreeChange]) -> [String] {
		Set(
			changes.flatMap { change in
				change.workingTreeState == .renamed
					? [change.path, change.previousPath].compactMap { $0 }
					: [change.path]
			}
		).sorted()
	}

	public func requestUnstageFromAmend(
		change: GitAmendChange,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			guard let base = try await requestAmendBase(at: repositoryURL) else {
				throw GitRepositoryError.invalidOutput
			}
			let paths = [change.path, change.previousPath].compactMap { $0 }
			_ = try await runner.requestRun(
				arguments: ["--literal-pathspecs", "reset", base, "--"] + paths,
				at: repositoryURL
			)
		}
	}

	public func requestCommit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
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
	}

	public func requestCommitPlanInput(at repositoryURL: URL) async throws -> GitCommitPlanInput {
		try await requestEnsureIdle(at: repositoryURL)
		guard let branchReference = try await requestCommitPlanBranchReference(at: repositoryURL)
		else { throw GitCommitPlanError.repositoryChanged }
		let head = try await requestCommitPlanHead(at: repositoryURL)
		let entries = try await runner.requestRun(
			arguments: ["ls-files", "--stage", "-z"], at: repositoryURL
		).standardOutput
		let changes = try await requestWorkingTreeChanges(at: repositoryURL).filter(\.isStaged)
		var units: [GitCommitUnit] = []
		for change in changes {
			try Task.checkCancellation()
			let diff = try await runner.requestRun(
				arguments: [
					"--literal-pathspecs", "diff", "--cached", "--binary", "--full-index",
					"--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--unified=0",
					"--", change.path,
				] + [change.previousPath].compactMap { $0 },
				at: repositoryURL
			).standardOutput
			units.append(contentsOf: try GitCommitUnitParser.parse(diff, path: change.path))
		}
		let recentMessages: [String]
		if let head {
			let messages = try await runner.requestRun(
				arguments: [
					"log", "-8", "--no-merges", "--no-show-signature", "--no-notes", "--format=%B%x00", head,
					"--",
				],
				at: repositoryURL
			).standardOutput
			recentMessages = messages.split(separator: "\0").map {
				String(
					String($0).trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.prefix(512))
			}.filter { !$0.isEmpty }
		} else {
			recentMessages = []
		}
		let currentEntries = try await runner.requestRun(
			arguments: ["ls-files", "--stage", "-z"], at: repositoryURL
		).standardOutput
		guard entries == currentEntries, head == (try await requestCommitPlanHead(at: repositoryURL)),
			branchReference == (try await requestCommitPlanBranchReference(at: repositoryURL))
		else { throw GitCommitPlanError.repositoryChanged }
		return GitCommitPlanInput(
			headHash: head, indexFingerprint: GitCommitUnitParser.fingerprint(entries), units: units,
			recentCommitMessages: recentMessages, branchReference: branchReference)
	}

	public func requestCommitTask(
		_ task: GitCommitTask,
		expecting input: GitCommitPlanInput,
		at repositoryURL: URL
	) async throws {
		guard task.hasValidMessage, !task.unitIDs.isEmpty,
			Set(task.unitIDs).count == task.unitIDs.count,
			Set(task.unitIDs).isSubset(of: Set(input.units.map(\.id)))
		else { throw GitCommitPlanError.invalidPlan }
		try await requestMutation(at: repositoryURL) {
			let indexPath = try await runner.requestRun(
				arguments: ["rev-parse", "--path-format=absolute", "--git-path", "index"],
				at: repositoryURL
			).standardOutput.trimmingCharacters(in: .newlines)
			let transaction: GitCommitIndexTransaction
			do {
				transaction = try GitCommitIndexTransaction(indexURL: URL(fileURLWithPath: indexPath))
			} catch let error as POSIXError where error.code == .EEXIST {
				throw GitRepositoryError.commandFailed(
					"Another Git process is updating staged changes. Wait for it to finish and retry.")
			}
			defer { withExtendedLifetime(transaction) {} }
			guard try await requestCommitPlanInput(at: repositoryURL) == input else {
				throw GitCommitPlanError.repositoryChanged
			}
			let environment = ["GIT_INDEX_FILE": transaction.temporaryIndexURL.path]
			_ = try await runner.requestRun(
				arguments: input.headHash.map { ["read-tree", $0] } ?? ["read-tree", "--empty"],
				at: repositoryURL, environment: environment)
			let selected = input.units.filter { task.unitIDs.contains($0.id) }
			let patch = try GitCommitUnitParser.combinedPatch(for: selected)
			_ = try await runner.requestRun(
				arguments: ["apply", "--cached", "--unidiff-zero", "--whitespace=nowarn", "-"],
				at: repositoryURL, standardInput: patch, environment: environment)
			let subject = task.subject.trimmingCharacters(in: .whitespacesAndNewlines)
			let body = task.body.trimmingCharacters(in: .whitespacesAndNewlines)
			guard try await requestCommitPlanHead(at: repositoryURL) == input.headHash,
				try await requestCommitPlanBranchReference(at: repositoryURL) == input.branchReference
			else {
				throw GitCommitPlanError.repositoryChanged
			}
			_ = try await runner.requestRun(
				arguments: ["commit", "--file", "-"], at: repositoryURL,
				standardInput: body.isEmpty ? subject : subject + "\n\n" + body,
				environment: environment)
		}
	}

	private func requestCommitPlanHead(at repositoryURL: URL) async throws -> String? {
		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "--quiet", "HEAD"], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1])
		let hash = result.standardOutput.trimmingCharacters(in: .newlines)
		return hash.isEmpty ? nil : hash
	}

	private func requestCommitPlanBranchReference(at repositoryURL: URL) async throws -> String? {
		let result = try await runner.requestRun(
			arguments: ["symbolic-ref", "--quiet", "HEAD"], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1])
		let reference = result.standardOutput.trimmingCharacters(in: .newlines)
		return reference.hasPrefix("refs/heads/") ? reference : nil
	}

	public func requestAmendWithoutEditingMessage(at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			_ = try await runner.requestRun(
				arguments: ["commit", "--amend", "--no-edit"],
				at: repositoryURL,
				environment: operationEnvironment
			)
		}
	}

	public func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: ["switch", "--no-guess", "--no-overwrite-ignore", "--", name], at: repositoryURL)
		}
	}

	public func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: ["switch", "--no-overwrite-ignore", "-c", name], at: repositoryURL)
		}
	}

	public func requestCreateBranch(
		named name: String,
		from commitHash: String,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: ["switch", "--no-overwrite-ignore", "-c", name, commitHash],
				at: repositoryURL
			)
		}
	}

	public func requestCheckoutCommit(_ commitHash: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			guard try await requestWorkingTreeChanges(at: repositoryURL).isEmpty else {
				throw GitRepositoryError.commandFailed(
					"변경 사항을 먼저 commit하거나 stash한 뒤 commit을 checkout해 주세요."
				)
			}
			_ = try await runner.requestRun(
				arguments: ["switch", "--no-overwrite-ignore", "--detach", "--", commitHash],
				at: repositoryURL
			)
		}
	}

	public func requestCreateTrackingBranch(
		named name: String,
		tracking remoteBranch: String,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			let reference =
				remoteBranch.hasPrefix("refs/remotes/")
				? remoteBranch : "refs/remotes/\(remoteBranch)"
			_ = try await runner.requestRun(
				arguments: ["switch", "--no-overwrite-ignore", "--track", "-c", name, reference],
				at: repositoryURL
			)
		}
	}

	public func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			_ = try await runner.requestRun(arguments: ["branch", "-d", "--", name], at: repositoryURL)
		}
	}

	public func requestRenameBranch(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestValidateReference(newName, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: ["branch", "-m", "--", name, newName], at: repositoryURL)
		}
	}

	public func requestMergeBranch(named name: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(name, prefix: "refs/heads/", at: repositoryURL)
			try await requestMerge(reference: "refs/heads/\(name)", at: repositoryURL)
		}
	}

	private func requestMerge(reference: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		do {
			_ = try await runner.requestRun(
				arguments: ["merge", "--no-edit", "--", reference],
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
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(branchName, prefix: "refs/heads/", at: repositoryURL)
			try await requestRebase(reference: "refs/heads/\(branchName)", at: repositoryURL)
		}
	}

	private func requestRebase(reference: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		try await requestOperationStart(
			arguments: ["rebase", reference],
			expectedOperation: .rebase,
			at: repositoryURL
		)
	}

	public func requestCherryPick(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
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
	}

	public func requestRevert(
		commitHash: String,
		mainline: Int?,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
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
	}

	public func requestResolveConflict(
		_ conflict: GitConflict,
		using resolution: GitConflictResolution,
		expecting content: GitConflictContent,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			let root = try await requestRepositoryRoot(at: repositoryURL).resolvingSymlinksInPath()
			let indexURL = try await requestIndexURL(at: root)
			let index = try GitCommitIndexTransaction(indexURL: indexURL)
			guard try await requestConflictContent(for: conflict, at: root) == content else {
				throw changedConflict()
			}
			let path = conflict.path
			let stages: [[String]] = try await runner.requestRun(
				arguments: ["--literal-pathspecs", "ls-files", "--unmerged", "-z", "--", path], at: root
			).standardOutput.split(separator: "\0").compactMap { entry in
				guard let fields = entry.split(separator: "\t", maxSplits: 1).first?.split(separator: " "),
					fields.count == 3
				else { return nil }
				return fields.map(String.init)
			}
			guard let hash = stages.first?[1] else { throw changedConflict() }
			let stage = resolution == .ours ? "2" : "3"
			let selected = stages.first { $0.count == 3 && $0[2] == stage }
			let hasStage = resolution == .ours ? conflict.hasOurs : conflict.hasTheirs
			guard (selected != nil) == hasStage else { throw changedConflict() }
			let transaction = try await makeDiscardTransaction(at: root)
			if hasStage {
				_ = try await runner.requestRun(
					arguments: [
						"checkout-index", "--stage=\(stage)",
						"--prefix=\(transaction.replacementsURL.path)/", "-z", "--stdin",
					], at: root, standardInput: path + "\0")
			}
			try FileManager.default.copyItem(at: indexURL, to: index.temporaryIndexURL)
			var update = "0 \(String(repeating: "0", count: hash.count))\t\(path)\0"
			if let selected {
				update += "\(selected[0]) \(selected[1])\t\(path)\0"
			}
			_ = try await runner.requestRun(
				arguments: ["update-index", "-z", "--index-info"], at: root, standardInput: update,
				environment: ["GIT_INDEX_FILE": index.temporaryIndexURL.path])
			do {
				try transaction.capture(path: path)
				guard
					try conflictWorkingTreeData(path: path, in: transaction.originalsURL)
						== content.workingTreeData
				else { throw changedConflict() }
				try Task.checkCancellation()
				if hasStage { try transaction.installReplacement(for: path) }
				try index.installIndex()
			} catch {
				throw discardRollbackError(transaction, cause: error)
			}
			try archiveOriginals(in: transaction)
		}
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
		let requestedWorkingTreeData = try conflictWorkingTreeData(
			path: conflict.path, in: repositoryURL)
		let stageContents = try await (baseData, currentData, incomingData)
		let workingTreeData = requestedWorkingTreeData
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
		expecting expectedContents: String,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			let data = try await requestFileContents(at: conflict.path, in: repositoryURL)
			guard let contents = String(data: data, encoding: .utf8) else {
				throw GitRepositoryError.invalidOutput
			}
			let hunks = GitConflictMarkerParser.parse(contents)
			guard contents == expectedContents, hunks.indices.contains(hunk.index),
				hunks[hunk.index] == hunk
			else {
				throw GitRepositoryError.commandFailed(
					"The conflict has changed. Review the current file before resolving it.")
			}
			let resolvedContents = try GitConflictMarkerParser.resolve(
				hunk.index,
				using: resolution,
				in: contents
			)
			let root = try await requestRepositoryRoot(at: repositoryURL).resolvingSymlinksInPath()
			let transaction = try await makeDiscardTransaction(at: root)
			let path = conflict.path
			do {
				try transaction.capture(path: path)
				guard try conflictWorkingTreeData(path: path, in: transaction.originalsURL) == data else {
					throw changedConflict()
				}
				let original = transaction.originalsURL.appending(path: path)
				let attributes = try FileManager.default.attributesOfItem(atPath: original.path)
				guard attributes[.type] as? FileAttributeType == .typeRegular else {
					throw GitRepositoryError.invalidFilePath
				}
				let replacement = transaction.replacementsURL.appending(path: path)
				try FileManager.default.createDirectory(
					at: replacement.deletingLastPathComponent(), withIntermediateDirectories: true)
				try Data(resolvedContents.utf8).write(to: replacement)
				if let permissions = attributes[.posixPermissions] {
					try FileManager.default.setAttributes(
						[.posixPermissions: permissions], ofItemAtPath: replacement.path)
				}
				try Task.checkCancellation()
				try transaction.installReplacement(for: path)
			} catch {
				throw discardRollbackError(transaction, cause: error)
			}
			try archiveOriginals(in: transaction)
		}
	}

	public func requestMarkConflictResolved(path: String, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestStageResolvedPath(path, at: repositoryURL)
		}
	}

	private func requestStageResolvedPath(_ path: String, at repositoryURL: URL) async throws {
		_ = try await runner.requestRun(
			arguments: ["--literal-pathspecs", "add", "-A", "--", path], at: repositoryURL)
	}

	private func requestConflictStageData(
		_ stage: Int,
		exists: Bool,
		path: String,
		at repositoryURL: URL
	) async throws -> Data? {
		guard exists else { return nil }
		return try await requestBlobData(
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
		try await requestMutation(at: repositoryURL) {
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
	}

	public func requestReset(
		to commitHash: String,
		mode: GitResetMode,
		expecting context: GitResetContext,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			let state = try await requestOperationState(at: repositoryURL)
			guard state.isIdle, !state.isDetached else {
				throw GitRepositoryError.commandFailed(
					"Reset is unavailable while HEAD is detached or an operation is in progress."
				)
			}
			try await requestValidateResetContext(context, at: repositoryURL)
			let target = try await runner.requestRun(
				arguments: ["rev-parse", "--verify", "--end-of-options", "\(commitHash)^{commit}"],
				at: repositoryURL
			).standardOutput.trimmingCharacters(in: .newlines)
			if mode == .hard {
				try await requestProtectUntrackedFiles(from: target, at: repositoryURL)
				try await requestHardReset(to: target, expecting: context, at: repositoryURL)
				return
			}
			try await requestValidateResetContext(context, at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: ["reset", "--\(mode.rawValue)", target, "--"],
				at: repositoryURL
			)
		}
	}

	private func requestHardReset(
		to target: String, expecting context: GitResetContext, at repositoryURL: URL
	) async throws {
		let root = try await requestRepositoryRoot(at: repositoryURL).resolvingSymlinksInPath()
		let index = try await GitCommitIndexTransaction(indexURL: requestIndexURL(at: root))
		let environment = ["GIT_INDEX_FILE": index.temporaryIndexURL.path]
		let before = try await resetIndexEntries(at: root)
		_ = try await runner.requestRun(
			arguments: ["read-tree", target], at: root, environment: environment)
		let after = try await resetIndexEntries(at: root, environment: environment)
		let excluded = try await requestSparseResetPaths(
			Set(after.keys), at: root, environment: environment)
		let dirty = try await runner.requestRun(
			arguments: ["diff-files", "--name-only", "-z", "--ignore-submodules=all"], at: root
		)
		.standardOutput.split(separator: "\0").map(String.init)
		let changedPaths = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
		let paths = Set(changedPaths).union(dirty)
		let captures = paths.filter { path in
			before[path].map { !$0.hasPrefix("S ") && !$0.dropFirst(2).hasPrefix("160000 ") } == true
		}.sorted()
		let replacements = paths.filter { path in
			!excluded.contains(path) && after[path].map { !$0.dropFirst(2).hasPrefix("160000 ") } == true
		}.sorted()
		let transaction = try await makeDiscardTransaction(at: root)
		if !replacements.isEmpty {
			_ = try await runner.requestRun(
				arguments: [
					"checkout-index", "--prefix=\(transaction.replacementsURL.path)/", "-z", "--stdin",
				],
				at: root, standardInput: replacements.joined(separator: "\0") + "\0",
				environment: environment)
		}
		let reference = "refs/heads/\(context.branchName)"
		do {
			try await requestValidateResetContext(context, at: root)
			for path in captures {
				try Task.checkCancellation()
				try transaction.capture(path: path)
				_ = try discardFileFingerprintType(path: path, in: transaction.originalsURL)
			}
			let replacingPaths = Set(replacements)
			var replacedDirectories: Set<String> = []
			for path in captures {
				var ancestors: [String] = []
				var parent = path[...]
				while let slash = parent.lastIndex(of: "/") {
					parent = parent[..<slash]
					ancestors.append(String(parent))
					if replacingPaths.contains(String(parent)) {
						replacedDirectories.formUnion(ancestors)
						break
					}
				}
			}
			for path in replacedDirectories.sorted(by: { $0.utf8.count > $1.utf8.count }) {
				try transaction.removeEmptyDirectory(at: path)
			}
			for path in replacements {
				try transaction.validateReplacementDestination(for: path)
			}
			for path in replacements {
				try Task.checkCancellation()
				try transaction.installReplacement(for: path)
			}
			try await requestValidateResetContext(context, at: root)
			try Task.checkCancellation()
			let update =
				"update \(reference) \(target) \(context.headHash)\nupdate ORIG_HEAD \(context.headHash)\n"
			_ = try await Task {
				try await runner.requestRun(
					arguments: ["update-ref", "-m", "reset: moving to \(target)", "--stdin"],
					at: root, standardInput: update)
			}.value
			do {
				try index.installIndex()
			} catch {
				_ = try? await Task {
					try await runner.requestRun(
						arguments: ["update-ref", reference, context.headHash, target], at: root)
				}.value
				throw error
			}
		} catch {
			throw discardRollbackError(transaction, cause: error)
		}
		try archiveOriginals(in: transaction)
	}

	private func resetIndexEntries(at root: URL, environment: [String: String] = [:]) async throws
		-> [String: String]
	{
		let result = try await runner.requestRun(
			arguments: ["ls-files", "-t", "--stage", "-z"], at: root, environment: environment)
		var entries: [String: String] = [:]
		for record in result.standardOutputData.split(separator: 0) {
			guard let entry = String(data: record, encoding: .utf8), let tab = entry.firstIndex(of: "\t")
			else { throw GitRepositoryError.invalidOutput }
			let path = String(entry[entry.index(after: tab)...])
			guard entries.updateValue(String(entry[..<tab]), forKey: path) == nil else {
				throw GitRepositoryError.invalidOutput
			}
		}
		return entries
	}

	private func requestSparseResetPaths(
		_ paths: Set<String>, at root: URL, environment: [String: String]
	) async throws -> Set<String> {
		guard !paths.isEmpty else { return [] }
		let sparse = try await runner.requestRun(
			arguments: ["config", "--bool", "--get", "core.sparseCheckout"], at: root,
			acceptedTerminationStatuses: [0, 1])
		guard sparse.standardOutput == "true\n" else { return [] }
		let included = try await runner.requestRun(
			arguments: ["sparse-checkout", "check-rules", "-z"], at: root,
			standardInput: paths.sorted().joined(separator: "\0") + "\0"
		).standardOutput.split(separator: "\0").map(String.init)
		let excluded = paths.subtracting(included)
		if !excluded.isEmpty {
			_ = try await runner.requestRun(
				arguments: ["update-index", "--skip-worktree", "-z", "--stdin"], at: root,
				standardInput: excluded.sorted().joined(separator: "\0") + "\0",
				environment: environment)
		}
		return excluded
	}

	private func discardFileFingerprintType(path: String, in directory: URL) throws
		-> FileAttributeType?
	{
		do {
			let file = directory.appending(path: path)
			let type =
				try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType
			guard type == .typeRegular || type == .typeSymbolicLink else {
				throw GitRepositoryError.commandFailed("A selected path is no longer an individual file.")
			}
			return type
		} catch let error as CocoaError
			where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
		{
			return nil
		}
	}

	public func requestCreateTag(
		named name: String,
		message: String,
		commitHash: String,
		at repositoryURL: URL
	) async throws {
		try await requestValidateReference(name, prefix: "refs/tags/", at: repositoryURL)
		let arguments =
			message.isEmpty
			? ["tag", "--", name, commitHash]
			: ["tag", "-a", "-m", message, "--", name, commitHash]
		_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
	}

	public func requestDeleteTag(_ tag: GitTag, at repositoryURL: URL) async throws {
		try await requestValidateReference(tag.name, prefix: "refs/tags/", at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["update-ref", "--no-deref", "-d", "refs/tags/\(tag.name)", tag.objectHash],
			at: repositoryURL)
	}

	@discardableResult public func requestCreateStash(
		message: String,
		includeUntracked: Bool = true,
		at repositoryURL: URL
	) async throws -> RepositoryStashOutcome {
		return try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			let changes = try await requestWorkingTreeChanges(at: repositoryURL)
			guard
				changes.contains(where: {
					includeUntracked || $0.isStaged || $0.workingTreeState != .untracked
				})
			else { return .nothingToSave }
			let before = try await requestStashes(at: repositoryURL)
			var arguments = ["stash", "push"]
			if includeUntracked {
				arguments.append("--include-untracked")
			}
			if !message.isEmpty {
				arguments.append(contentsOf: ["--message", message])
			}
			let outcome = try await requestStashMutation(arguments: arguments, at: repositoryURL)
			guard outcome == .completed else { return outcome }
			let after = try await requestStashes(at: repositoryURL)
			return after.count > before.count || after.first?.hash != before.first?.hash
				? .completed : .nothingToSave
		}
	}

	@discardableResult public func requestApplyStash(_ stash: GitStash, at repositoryURL: URL)
		async throws -> RepositoryStashOutcome
	{
		return try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			let current = try await requestCurrentStash(stash, at: repositoryURL)
			return try await requestStashMutation(
				arguments: ["stash", "apply", "--index", "--", current.hash],
				at: repositoryURL, reportsConflicts: true
			)
		}
	}

	@discardableResult public func requestPopStash(_ stash: GitStash, at repositoryURL: URL)
		async throws -> RepositoryStashOutcome
	{
		return try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			let directory = try await requestStashDirectory(at: repositoryURL)
			let current = try await requestCurrentStash(stash, at: repositoryURL)
			let outcome = try await requestStashMutation(
				arguments: ["stash", "apply", "--index", "--", current.hash],
				at: repositoryURL, reportsConflicts: true
			)
			guard outcome == .completed else { return outcome }
			do {
				return try await requestDropStashEntry(current, in: directory, at: repositoryURL)
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				return .failed(
					"The stash was applied, but its removal could not finish. \(error.localizedDescription)")
			}
		}
	}

	@discardableResult public func requestDropStash(_ stash: GitStash, at repositoryURL: URL)
		async throws -> RepositoryStashOutcome
	{
		return try await requestMutation(at: repositoryURL) {
			let directory = try await requestStashDirectory(at: repositoryURL)
			return try await requestDropStashEntry(stash, in: directory, at: repositoryURL)
		}
	}

	private func requestStashDirectory(at repositoryURL: URL) async throws -> URL {
		let format = try await runner.requestRun(
			arguments: ["rev-parse", "--show-ref-format"], at: repositoryURL)
		guard format.standardOutput.trimmingCharacters(in: .newlines) == "files" else {
			throw GitRepositoryError.commandFailed(
				"Safe stash deletion requires Git's files reference format. The stash was kept.")
		}
		let directory = try await runner.requestRun(
			arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		return URL(fileURLWithPath: directory)
	}

	private func requestDropStashEntry(_ stash: GitStash, in directory: URL, at repositoryURL: URL)
		async throws -> RepositoryStashOutcome
	{
		let editor = try GitStashReflogTransaction(gitDirectory: directory)
		let current = try await requestCurrentStash(stash, at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["update-ref", "refs/groves/stash-recovery/\(stash.hash)", stash.hash],
			at: repositoryURL)
		try Task.checkCancellation()
		try editor.drop(current)
		return .completed
	}

	public func requestFetch(remote name: String, at repositoryURL: URL) async throws {
		try await requestFetch(remote: name, reference: nil, at: repositoryURL)
	}

	private func requestFetch(remote name: String, reference: String?, at repositoryURL: URL)
		async throws
	{
		let requiresSSHTrustScope = try await requestRemoteUsesSSH(
			named: name,
			usesPushURL: false,
			at: repositoryURL
		)
		_ = try await runner.requestRun(
			arguments: ["fetch", "--", name] + [reference].compactMap { $0 },
			at: repositoryURL,
			isNetworkOperation: true,
			requiresSSHTrustScope: requiresSSHTrustScope
		)
	}

	public func requestFetchAll(at repositoryURL: URL, allowsUserInteraction: Bool) async throws {
		let remoteNames = try await requestRemoteNames(at: repositoryURL)
		var requiresSSHTrustScope = false
		for remoteName in remoteNames {
			let remoteUsesSSH = try await requestRemoteUsesSSH(
				named: remoteName,
				usesPushURL: false,
				at: repositoryURL
			)
			requiresSSHTrustScope = requiresSSHTrustScope || remoteUsesSSH
		}
		_ = try await runner.requestRun(
			arguments: ["fetch", "--all"],
			at: repositoryURL,
			isNetworkOperation: true,
			requiresSSHTrustScope: requiresSSHTrustScope,
			allowsUserInteraction: allowsUserInteraction
		)
	}

	public func requestPreparePull(expecting branch: GitBranch, at repositoryURL: URL) async throws
		-> RepositoryPullOutcome
	{
		return try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			guard
				let currentBranch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
				currentBranch.name == branch.name, currentBranch.hash == branch.hash,
				currentBranch.upstream == branch.upstream
			else {
				throw GitRepositoryError.commandFailed(
					"The current branch, HEAD or upstream has changed. Review the branch before pulling.")
			}
			guard
				let upstream = currentBranch.upstream,
				let remoteName = try await requestConfigurationValue(
					"branch.\(currentBranch.name).remote", at: repositoryURL),
				let mergeReference = try await requestConfigurationValue(
					"branch.\(currentBranch.name).merge", at: repositoryURL)
			else {
				throw GitRepositoryError.commandFailed(
					"현재 브랜치에 upstream이 없습니다. 먼저 upstream을 설정해 주세요."
				)
			}

			try await requestFetch(remote: remoteName, reference: mergeReference, at: repositoryURL)
			guard
				let updatedBranch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
				updatedBranch.name == currentBranch.name, updatedBranch.hash == currentBranch.hash,
				updatedBranch.upstream == upstream
			else {
				throw GitRepositoryError.commandFailed(
					"The current branch or upstream has changed. Pull again to review its history.")
			}
			let upstreamHash: String
			do {
				upstreamHash = try await runner.requestRun(
					arguments: ["rev-parse", "--verify", "--end-of-options", "@{upstream}^{commit}"],
					at: repositoryURL
				).standardOutput.trimmingCharacters(in: .newlines)
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				throw GitRepositoryError.commandFailed(
					"The upstream branch \(upstream) is unavailable. Check the remote branch and tracking configuration before pulling."
				)
			}

			switch (updatedBranch.aheadCount, updatedBranch.behindCount) {
			case (0, 0):
				return .upToDate
			case (let aheadCount, 0):
				return .aheadOnly(aheadCount: aheadCount)
			case (0, _):
				_ = try await runner.requestRun(
					arguments: ["merge", "--ff-only", "--", upstreamHash],
					at: repositoryURL
				)
				return .fastForwarded
			case (let aheadCount, let behindCount):
				return .diverged(
					RepositoryPullDivergence(
						branchName: updatedBranch.name,
						headHash: updatedBranch.hash,
						upstream: upstream,
						upstreamHash: upstreamHash,
						aheadCount: aheadCount,
						behindCount: behindCount
					)
				)
			}
		}
	}

	public func requestResolvePull(
		_ divergence: RepositoryPullDivergence,
		using resolution: RepositoryPullResolution,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			guard try await requestWorkingTreeChanges(at: repositoryURL).isEmpty else {
				throw GitRepositoryError.commandFailed(
					"변경 사항을 먼저 commit하거나 stash한 뒤 pull을 계속해 주세요."
				)
			}
			guard
				let currentBranch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
				currentBranch.name == divergence.branchName,
				currentBranch.hash == divergence.headHash,
				currentBranch.upstream == divergence.upstream,
				try await runner.requestRun(
					arguments: ["rev-parse", "--verify", "--end-of-options", "@{upstream}^{commit}"],
					at: repositoryURL
				).standardOutput.trimmingCharacters(in: .newlines) == divergence.upstreamHash
			else {
				throw GitRepositoryError.commandFailed(
					"The current branch, HEAD or upstream has changed. Pull again to review its history.")
			}
			switch resolution {
			case .rebase:
				try await requestRebase(reference: divergence.upstreamHash, at: repositoryURL)
			case .merge:
				try await requestMerge(reference: divergence.upstreamHash, at: repositoryURL)
			}
		}
	}

	public func requestPush(_ target: GitPushTarget, at repositoryURL: URL) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			let command = try await requestPushCommand(for: target, at: repositoryURL)
			let requiresSSHTrustScope = try await requestRemoteUsesSSH(
				named: command.remoteName, usesPushURL: true, at: repositoryURL)
			_ = try await runner.requestRun(
				arguments: command.arguments,
				at: repositoryURL,
				isNetworkOperation: true,
				requiresSSHTrustScope: requiresSSHTrustScope
			)
		}
	}

	public func requestForcePush(
		_ target: GitPushTarget, expecting branch: GitBranch, remotes: [GitRemote],
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestEnsureIdle(at: repositoryURL)
			guard
				let current = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
				current.name == branch.name, current.hash == branch.hash,
				current.upstream == branch.upstream,
				current.upstreamRemoteName == branch.upstreamRemoteName,
				current.upstreamRemoteReference == branch.upstreamRemoteReference
			else {
				throw GitRepositoryError.commandFailed(
					"The current branch, HEAD or upstream has changed. Review the branch before force pushing."
				)
			}
			let command = try await requestPushCommand(for: target, at: repositoryURL)
			guard command.sourceReference == "refs/heads/\(branch.name)" else {
				throw GitRepositoryError.commandFailed("The current branch changed. Review it again.")
			}
			if case .upstream = target {
				let reviewedDestination =
					command.remoteName == branch.upstreamRemoteName
					? branch.upstreamRemoteReference : "refs/heads/\(branch.name)"
				guard command.destinationReference == reviewedDestination else {
					throw GitRepositoryError.commandFailed(
						"The upstream changed. Review the destination again.")
				}
			}
			if case .upstream(_, nil) = target, branch.pushRemoteName != command.remoteName {
				throw GitRepositoryError.commandFailed(
					"The push remote changed. Review the destination again.")
			}
			guard let remote = remotes.first(where: { $0.name == command.remoteName }) else {
				throw GitRepositoryError.commandFailed(
					"The push remote changed. Review the destination again.")
			}
			let destination = String(command.destinationReference.dropFirst("refs/heads/".count))
			let reviewedHash = remote.branches.first { $0.name == destination }?.hash
			let isConfiguredUpstream =
				branch.upstreamRemoteName == command.remoteName
				&& branch.upstreamRemoteReference == command.destinationReference
			let expectedHash = (isConfiguredUpstream ? branch.customUpstreamHash : nil) ?? reviewedHash
			if let expectedHash {
				try await requestValidateForcePushHistory(
					expecting: expectedHash, from: command.sourceReference, at: repositoryURL)
			}
			try await requestPinnedPush(
				remote: command.remoteName, urls: remote.effectivePushURLs,
				lease: "\(command.destinationReference):\(expectedHash ?? "")",
				refspec: "\(branch.hash):\(command.destinationReference)", at: repositoryURL)
			if case .setUpstream = target {
				do {
					try await requestModifyConfiguration(at: repositoryURL) { configuration in
						guard
							try await self.requestRemoteURLs(
								named: command.remoteName, usesPushURL: true, at: repositoryURL)
								== remote.effectivePushURLs
						else {
							throw GitRepositoryError.commandFailed("The remote changed while pushing.")
						}
						try await self.requestSetConfigurationValue(
							command.remoteName, for: "branch.\(branch.name).remote", in: configuration,
							at: repositoryURL)
						try await self.requestSetConfigurationValue(
							command.destinationReference, for: "branch.\(branch.name).merge",
							in: configuration, at: repositoryURL)
					}
				} catch {
					throw GitRepositoryError.commandFailed(
						"The push completed, but the upstream could not be saved. \(error.localizedDescription)"
					)
				}
			}
		}
	}

	public func requestPushTags(remote name: String, at repositoryURL: URL) async throws {
		try await requestEnsureIdle(at: repositoryURL)
		let requiresSSHTrustScope = try await requestRemoteUsesSSH(
			named: name,
			usesPushURL: true,
			at: repositoryURL
		)
		_ = try await runner.requestRun(
			arguments: ["push", name, "--tags"],
			at: repositoryURL,
			isNetworkOperation: true,
			requiresSSHTrustScope: requiresSSHTrustScope
		)
	}

	public func requestAddRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {
		try await requestValidateReference(name, prefix: "refs/remotes/", at: repositoryURL)
		try validateRemoteURLs(fetchURL: fetchURL, pushURL: pushURL)
		try await requestModifyConfiguration(at: repositoryURL) { configurationURL in
			let remotes = try await self.requestRemoteConfiguration(at: repositoryURL)
			guard !remotes.contains(where: { $0.name == name }) else {
				throw GitRepositoryError.commandFailed("A remote with this name already exists.")
			}
			try await self.requestSetConfigurationValue(
				fetchURL, for: "remote.\(name).url", in: configurationURL, at: repositoryURL)
			try await self.requestSetConfigurationValue(
				"+refs/heads/*:refs/remotes/\(name)/*", for: "remote.\(name).fetch",
				in: configurationURL, at: repositoryURL)
			try await self.requestSetConfigurationValue(
				pushURL, for: "remote.\(name).pushurl", in: configurationURL, at: repositoryURL)
		}
	}

	public func requestRenameRemote(
		named name: String,
		to newName: String,
		at repositoryURL: URL
	) async throws {
		try await requestValidateReference(name, prefix: "refs/remotes/", at: repositoryURL)
		try await requestValidateReference(newName, prefix: "refs/remotes/", at: repositoryURL)
		_ = try await runner.requestRun(
			arguments: ["remote", "rename", "--", name, newName], at: repositoryURL)
	}

	public func requestUpdateRemote(
		named name: String,
		fetchURL: String,
		pushURL: String?,
		at repositoryURL: URL
	) async throws {
		try await requestValidateReference(name, prefix: "refs/remotes/", at: repositoryURL)
		try validateRemoteURLs(fetchURL: fetchURL, pushURL: pushURL)
		try await requestModifyConfiguration(at: repositoryURL) { configurationURL in
			let configured = try await self.requestRemoteConfiguration(at: repositoryURL)
			let local = try await self.requestConfiguredRemotes(from: configurationURL, at: repositoryURL)
			guard let remote = configured.first(where: { $0.name == name }) else {
				throw GitRepositoryError.commandFailed(
					"The remote no longer exists. Refresh and try again.")
			}
			guard !remote.hasMultipleURLs else {
				throw GitRepositoryError.commandFailed(
					"This remote has multiple URLs. Edit its URLs with Git to preserve all destinations.")
			}
			guard let localRemote = local.first(where: { $0.name == name }),
				localRemote.fetchURLs == remote.fetchURLs, localRemote.pushURLs == remote.pushURLs
			else {
				throw GitRepositoryError.commandFailed(
					"The remote URLs are defined outside the repository’s main configuration. Edit them in their original configuration file."
				)
			}
			try await self.requestSetConfigurationValue(
				fetchURL, for: "remote.\(name).url", in: configurationURL, at: repositoryURL)
			try await self.requestSetConfigurationValue(
				pushURL, for: "remote.\(name).pushurl", in: configurationURL, at: repositoryURL)
		}
	}

	private func validateRemoteURLs(fetchURL: String, pushURL: String?) throws {
		for url in [fetchURL, pushURL].compactMap({ $0 })
		where url.isEmpty || url.hasPrefix("-")
			|| url.rangeOfCharacter(from: .controlCharacters) != nil
			|| GitRemoteURLValidator.containsEmbeddedCredential(url)
		{
			throw GitRepositoryError.invalidRemoteURL
		}
	}

	public func requestDeleteRemote(named name: String, at repositoryURL: URL) async throws {
		try await requestValidateReference(name, prefix: "refs/remotes/", at: repositoryURL)
		_ = try await runner.requestRun(arguments: ["remote", "remove", "--", name], at: repositoryURL)
	}

	public func requestDeleteRemoteBranch(
		_ branch: GitRemoteBranch,
		at repositoryURL: URL
	) async throws {
		try await requestMutation(at: repositoryURL) {
			try await requestValidateReference(branch.name, prefix: "refs/heads/", at: repositoryURL)
			try await requestEnsureIdle(at: repositoryURL)
			let reference = "refs/heads/\(branch.name)"
			try await requestPinnedPush(
				remote: branch.remoteName, urls: branch.pushURLs, lease: "\(reference):\(branch.hash)",
				refspec: ":\(reference)", at: repositoryURL)
		}
	}

	private func requestPinnedPush(
		remote: String, urls: [String], lease: String, refspec: String, at repositoryURL: URL
	) async throws {
		let current = try await requestRemoteURLs(named: remote, usesPushURL: true, at: repositoryURL)
		guard !urls.isEmpty, urls == current,
			!urls.contains(where: GitRemoteURLValidator.containsEmbeddedCredential)
		else {
			throw GitRepositoryError.commandFailed("The push destination changed. Review it again.")
		}
		let alias = "groves-push-\(UUID().uuidString)"
		let mappings = try await runner.requestRun(
			arguments: ["config", "-z", "--get-all", "remote.\(remote).fetch"], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1]
		).standardOutput.split(separator: "\0")
		var settings = mappings.map { ("remote.\(alias).fetch", String($0)) }
		for (index, url) in urls.enumerated() {
			let address = "\(alias)-\(index)"
			settings.append(("remote.\(alias).url", address))
			settings.append(("url.\(url).insteadOf", address))
		}
		var environment = ["GIT_CONFIG_COUNT": String(settings.count)]
		for (index, setting) in settings.enumerated() {
			environment["GIT_CONFIG_KEY_\(index)"] = setting.0
			environment["GIT_CONFIG_VALUE_\(index)"] = setting.1
		}
		_ = try await runner.requestRun(
			arguments: ["push", "--force-with-lease=\(lease)", "--", alias, refspec],
			at: repositoryURL, environment: environment, isNetworkOperation: true,
			requiresSSHTrustScope: urls.contains(where: GitRemoteURLValidator.isSSHRemote))
	}

	private func requestPushRemoteName(branchName: String, at repositoryURL: URL) async throws
		-> String?
	{
		for key in [
			"branch.\(branchName).pushRemote", "remote.pushDefault", "branch.\(branchName).remote",
		] {
			if let name = try await requestConfigurationValue(key, at: repositoryURL) { return name }
		}
		return nil
	}

	private func requestConfigurationValue(_ key: String, at repositoryURL: URL) async throws
		-> String?
	{
		let result = try await runner.requestRun(
			arguments: ["config", "--get", key], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1])
		let value = result.standardOutput.trimmingCharacters(in: .newlines)
		return value.isEmpty ? nil : value
	}

	private func requestRemoteNames(at repositoryURL: URL) async throws -> [String] {
		let result = try await runner.requestRun(arguments: ["remote"], at: repositoryURL)
		return result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
	}

	private func requestRemoteUsesSSH(
		named name: String,
		usesPushURL: Bool,
		at repositoryURL: URL
	) async throws -> Bool {
		let remoteURLs = try await requestRemoteURLs(
			named: name, usesPushURL: usesPushURL, at: repositoryURL)
		guard !remoteURLs.contains(where: GitRemoteURLValidator.containsEmbeddedCredential) else {
			throw GitRepositoryError.invalidRemoteURL
		}
		return remoteURLs.contains(where: GitRemoteURLValidator.isSSHRemote)
	}

	private func requestRemoteURLs(named name: String, usesPushURL: Bool, at repositoryURL: URL)
		async throws -> [String]
	{
		var arguments = ["remote", "get-url"]
		if usesPushURL {
			arguments.append("--push")
		}
		arguments.append(contentsOf: ["--all", name])
		let result = try await runner.requestRun(
			arguments: arguments,
			at: repositoryURL,
			acceptedTerminationStatuses: [0, 2]
		)
		return result.standardOutput.split(whereSeparator: \.isNewline).map(String.init)
	}

	private func requestPushCommand(for target: GitPushTarget, at repositoryURL: URL) async throws
		-> (
			arguments: [String], remoteName: String, sourceReference: String, destinationReference: String
		)
	{
		switch target {
		case .upstream(let branchName, let selectedRemoteName):
			guard
				let branch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
				branchName == nil || branch.name == branchName,
				branch.upstream != nil,
				let upstreamRemote = try await requestConfigurationValue(
					"branch.\(branch.name).remote", at: repositoryURL),
				let upstreamReference = try await requestConfigurationValue(
					"branch.\(branch.name).merge", at: repositoryURL),
				upstreamReference.hasPrefix("refs/heads/")
			else {
				throw GitRepositoryError.commandFailed(
					"현재 브랜치의 push 대상을 확인할 수 없습니다. 브랜치와 upstream 설정을 확인해 주세요.")
			}
			let remoteName: String
			if let selectedRemoteName {
				guard try await requestRemoteNames(at: repositoryURL).contains(selectedRemoteName) else {
					throw GitRepositoryError.commandFailed("The selected remote no longer exists.")
				}
				remoteName = selectedRemoteName
			} else {
				remoteName =
					try await requestPushRemoteName(branchName: branch.name, at: repositoryURL)
					?? upstreamRemote
			}
			let source = "refs/heads/\(branch.name)"
			let destination = remoteName == upstreamRemote ? upstreamReference : source
			return (
				["push", "--", remoteName, "\(source):\(destination)"], remoteName, source, destination
			)
		case .setUpstream(let remoteName, let branchName):
			try await requestValidateReference(branchName, prefix: "refs/heads/", at: repositoryURL)
			let reference = "refs/heads/\(branchName)"
			return (
				["push", "--set-upstream", "--", remoteName, "\(reference):\(reference)"],
				remoteName, reference, reference
			)
		}
	}

	private func requestValidateForcePushHistory(
		expecting remoteHash: String, from source: String, at repositoryURL: URL
	) async throws {
		let currentHash = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "\(source)^{commit}"], at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		let reflog = try await runner.requestRun(
			arguments: ["reflog", "show", "--format=%H", source], at: repositoryURL)
		var seen: Set<String> = []
		let hashes =
			([currentHash] + reflog.standardOutput.split(whereSeparator: \.isNewline).map(String.init))
			.filter { seen.insert($0).inserted }
		for start in stride(from: 0, to: hashes.count, by: 64) {
			let chunk = Array(hashes[start..<min(start + 64, hashes.count)])
			let bases = try await runner.requestRun(
				arguments: ["merge-base", "--all", remoteHash] + chunk, at: repositoryURL,
				acceptedTerminationStatuses: [0, 1])
			if bases.standardOutput.split(whereSeparator: \.isNewline).contains(Substring(remoteHash)) {
				return
			}
		}
		throw GitRepositoryError.commandFailed(
			"The remote branch contains commits that have not been included in this local branch. Pull and review them before force pushing."
		)
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

	private func requestStashHash(_ hash: String, at repositoryURL: URL) async throws -> String {
		let resolved = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "--end-of-options", "\(hash)^{commit}"],
			at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		guard resolved == hash else { throw GitRepositoryError.invalidOutput }
		return resolved
	}

	private func requestCurrentStash(_ stash: GitStash, at repositoryURL: URL) async throws
		-> GitStash
	{
		let candidates = try await requestStashes(at: repositoryURL).filter {
			$0.hash == stash.hash && $0.subject == stash.subject
		}
		guard
			let current = candidates.first(where: { $0.reference == stash.reference })
				?? (candidates.count == 1 ? candidates.first : nil)
		else {
			throw GitRepositoryError.commandFailed(
				"The stash list has changed. Refresh and select the stash again.")
		}
		let actual = try await runner.requestRun(
			arguments: ["rev-parse", "--verify", "--end-of-options", "\(current.reference)^{commit}"],
			at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		guard actual == stash.hash else {
			throw GitRepositoryError.commandFailed(
				"The stash list has changed. Refresh and select the stash again.")
		}
		return current
	}

	private func requestStashMutation(
		arguments: [String], at repositoryURL: URL, reportsConflicts: Bool = false
	) async throws
		-> RepositoryStashOutcome
	{
		do {
			_ = try await runner.requestRun(arguments: arguments, at: repositoryURL)
			return .completed
		} catch is CancellationError {
			throw CancellationError()
		} catch {
			let state = reportsConflicts ? try? await requestOperationState(at: repositoryURL) : nil
			try Task.checkCancellation()
			return state?.hasConflicts == true ? .conflicted : .failed(error.localizedDescription)
		}
	}

	private func requestSetConfigurationValue(
		_ value: String?, for key: String, in configurationURL: URL, at repositoryURL: URL
	) async throws {
		if let value {
			_ = try await runner.requestRun(
				arguments: ["config", "--file", configurationURL.path, "--replace-all", "--", key, value],
				at: repositoryURL
			)
		} else {
			_ = try await runner.requestRun(
				arguments: ["config", "--file", configurationURL.path, "--unset-all", "--", key],
				at: repositoryURL,
				acceptedTerminationStatuses: [0, 5]
			)
		}
	}

	private func requestConfiguredRemotes(
		from configurationURL: URL, at repositoryURL: URL
	) async throws -> [GitRemote] {
		let result = try await runner.requestRun(
			arguments: [
				"config", "--file", configurationURL.path, "--no-includes",
				"--null", "--get-regexp", "^remote\\.",
			],
			at: repositoryURL, acceptedTerminationStatuses: [0, 1])
		return GitOutputParser.parseRemotes(result.standardOutput)
	}

	private func requestRemoteConfiguration(at repositoryURL: URL) async throws -> [GitRemote] {
		let result = try await runner.requestRun(
			arguments: ["config", "--null", "--get-regexp", "^remote\\."], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1])
		return GitOutputParser.parseRemotes(result.standardOutput)
	}

	private func requestModifyConfiguration(
		at repositoryURL: URL, _ operation: @Sendable (URL) async throws -> Void
	) async throws {
		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--path-format=absolute", "--git-path", "config"], at: repositoryURL)
		let url = URL(fileURLWithPath: result.standardOutput.trimmingCharacters(in: .newlines))
		do {
			let transaction = try GitConfigurationTransaction(configurationURL: url)
			try await operation(transaction.stagingURL)
			try transaction.commit()
		} catch let error as POSIXError where error.code == .EEXIST {
			throw GitRepositoryError.commandFailed(
				"Another Git process is updating this repository’s configuration. Wait for it to finish and retry."
			)
		}
	}

	private func requestValidateReference(_ name: String, prefix: String, at repositoryURL: URL)
		async throws
	{
		guard !name.isEmpty, !name.hasPrefix("-") else {
			throw GitRepositoryError.commandFailed("Enter a valid Git reference name.")
		}
		let reference = prefix + name
		let result = try await runner.requestRun(
			arguments: ["check-ref-format", "--normalize", reference], at: repositoryURL,
			acceptedTerminationStatuses: [0, 1])
		guard result.standardOutput.trimmingCharacters(in: .newlines) == reference else {
			throw GitRepositoryError.commandFailed("Enter a valid Git reference name.")
		}
	}

	private func requestMutation<Value: Sendable>(
		at repositoryURL: URL, _ operation: @Sendable () async throws -> Value
	) async throws -> Value {
		let directory = try await runner.requestRun(
			arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], at: repositoryURL
		).standardOutput.trimmingCharacters(in: .newlines)
		let url = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
		return try await GitRepositoryMutationCoordinator.shared.withMutation(
			at: url, operation: operation)
	}

	private func requestValidateResetContext(_ context: GitResetContext, at repositoryURL: URL)
		async throws
	{
		guard let branch = try await requestBranches(at: repositoryURL).first(where: \.isCurrent),
			branch.name == context.branchName, branch.hash == context.headHash
		else {
			throw GitRepositoryError.commandFailed(
				"The current branch or HEAD has changed. Open Reset again to review the new target.")
		}
	}

	private func requestProtectUntrackedFiles(from commitHash: String, at repositoryURL: URL)
		async throws
	{
		let root = try await requestRepositoryRoot(at: repositoryURL)
		let target = try await runner.requestRun(
			arguments: ["ls-tree", "-r", "--full-tree", "--name-only", "-z", commitHash], at: root)
		let untracked = try await runner.requestRun(
			arguments: ["ls-files", "--others", "--full-name", "-z"], at: root)
		let isCaseSensitive =
			try root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
			.volumeSupportsCaseSensitiveNames == true
		func pathKey(_ path: String) -> String {
			isCaseSensitive
				? path : path.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
		}
		func paths(in data: Data) throws -> [String] {
			try data.split(separator: 0).map { record in
				guard let path = String(data: record, encoding: .utf8) else {
					throw GitRepositoryError.invalidOutput
				}
				return path.hasSuffix("/") ? String(path.dropLast()) : path
			}
		}
		func parents(of path: String) -> [String] {
			var result: [String] = []
			var prefix = path
			while let separator = prefix.lastIndex(of: "/") {
				prefix = String(prefix[..<separator])
				result.append(prefix)
			}
			return result
		}
		let targetPaths = Set(try paths(in: target.standardOutputData).map(pathKey))
		let targetDirectories = Set(targetPaths.flatMap { parents(of: $0) })
		let collisions = try paths(in: untracked.standardOutputData).filter { path in
			let key = pathKey(path)
			return targetPaths.contains(key) || targetDirectories.contains(key)
				|| parents(of: key).contains(where: targetPaths.contains)
		}
		guard collisions.isEmpty else {
			let affectedPaths = collisions.prefix(3).joined(separator: ", ")
			throw GitRepositoryError.commandFailed(
				"Hard reset would overwrite untracked or ignored files: \(affectedPaths). Move these files before retrying."
			)
		}
	}

	private func requestValidateDiff(
		_ expectedDiff: String,
		for change: WorkingTreeChange,
		source: GitDiffSource,
		options: GitDiffOptions,
		at repositoryURL: URL
	) async throws {
		let currentDiff = try await requestDiff(
			for: change, source: source, options: options, at: repositoryURL)
		guard currentDiff == expectedDiff else {
			throw GitRepositoryError.commandFailed(
				"The diff has changed. Review the current changes before applying this action.")
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
			arguments: ["hash-object", "-t", "tree", "--stdin"],
			at: repositoryURL,
			standardInput: ""
		)
		return emptyTree.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func requestBlobData(
		revision: String?,
		path: String,
		at repositoryURL: URL
	) async throws -> Data? {
		guard let revision else { return nil }
		let object = revision.isEmpty ? ":\(path)" : "\(revision):\(path)"
		guard
			let sizeResult = try? await runner.requestRun(
				arguments: ["cat-file", "-s", object],
				at: repositoryURL
			),
			let byteCount = Int(
				sizeResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		else { return nil }
		guard byteCount <= Self.maximumPreviewByteCount else {
			throw GitRepositoryError.fileTooLarge
		}
		let result = try await runner.requestRun(
			arguments: ["show", object],
			at: repositoryURL
		)
		guard result.standardOutputData.count <= Self.maximumPreviewByteCount else {
			throw GitRepositoryError.fileTooLarge
		}
		return result.standardOutputData
	}

	private func requestWorkingTreeData(path: String, at repositoryURL: URL) async throws -> Data? {
		do {
			return try await requestFileContents(at: path, in: repositoryURL)
		} catch is CancellationError {
			throw CancellationError()
		} catch GitRepositoryError.fileTooLarge {
			throw GitRepositoryError.fileTooLarge
		} catch {
			return nil
		}
	}
}
