import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitOutputParserTests: XCTestCase {
	func testCloneRepositoryCreatesRepositoryInSelectedDirectory() async throws {
		let sourceRepositoryURL = try makeRepository()
		let destinationDirectoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesCloneTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: destinationDirectoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: sourceRepositoryURL)
			try? FileManager.default.removeItem(at: destinationDirectoryURL)
		}

		let clonedRepositoryURL = try await LocalGitRepository().requestCloneRepository(
			from: sourceRepositoryURL.absoluteString,
			into: destinationDirectoryURL
		)

		XCTAssertEqual(clonedRepositoryURL.lastPathComponent, sourceRepositoryURL.lastPathComponent)
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: clonedRepositoryURL.appending(path: ".git").path)
		)
	}

	func testParseWorkingTreeChangesSeparatesIndexAndWorkingTreeStates() {
		let output = "M  staged.swift\0 M unstaged.swift\0?? new.swift\0"

		let changes = GitOutputParser.parseWorkingTreeChanges(output)

		XCTAssertEqual(changes.count, 3)
		XCTAssertEqual(changes.first(where: { $0.path == "staged.swift" })?.indexState, .modified)
		XCTAssertEqual(
			changes.first(where: { $0.path == "unstaged.swift" })?.workingTreeState,
			.modified
		)
		XCTAssertEqual(changes.first(where: { $0.path == "new.swift" })?.workingTreeState, .untracked)
	}

	func testParseWorkingTreeChangesMergesDuplicateDeletedAndUntrackedPath() {
		let output = "D  tracked.txt\0?? tracked.txt\0"

		let changes = GitOutputParser.parseWorkingTreeChanges(output)

		XCTAssertEqual(changes.count, 1)
		XCTAssertEqual(changes.first?.path, "tracked.txt")
		XCTAssertEqual(changes.first?.indexState, .deleted)
		XCTAssertEqual(changes.first?.workingTreeState, .untracked)
	}

	func testParseConflictsPreservesKindsAndStageAvailability() {
		let zeroHash = String(repeating: "0", count: 40)
		let objectHash = String(repeating: "1", count: 40)
		let records = GitConflictKind.allCases.enumerated().map { index, kind in
			"u \(kind.rawValue) N... 100644 100644 100644 100644 \(index == 0 ? zeroHash : objectHash) \(objectHash) \(index == 1 ? zeroHash : objectHash) conflict-\(index).txt"
		}

		let conflicts = GitOutputParser.parseConflicts(records.joined(separator: "\0") + "\0")

		XCTAssertEqual(Set(conflicts.map(\.kind)), Set(GitConflictKind.allCases))
		XCTAssertEqual(conflicts.first(where: { $0.path == "conflict-0.txt" })?.hasBase, false)
		XCTAssertEqual(conflicts.first(where: { $0.path == "conflict-1.txt" })?.hasTheirs, false)
		XCTAssertTrue(conflicts.allSatisfy(\.hasOurs))
	}

	func testParseAmendChangesPreservesRenamePaths() {
		let output = "M\0Sources/App.swift\0R100\0Old.swift\0New.swift\0"

		let changes = GitOutputParser.parseAmendChanges(output)

		XCTAssertEqual(changes.count, 2)
		XCTAssertEqual(changes.first(where: { $0.path == "Sources/App.swift" })?.state, .modified)
		XCTAssertEqual(changes.first(where: { $0.path == "New.swift" })?.state, .renamed)
		XCTAssertEqual(changes.first(where: { $0.path == "New.swift" })?.previousPath, "Old.swift")
	}

	func testBuildFileTreeGroupsFilesByDirectory() {
		let nodes = GitOutputParser.buildFileTree(
			paths: ["Sources/App.swift", "Sources/Feature/View.swift", "README.md"]
		)

		XCTAssertEqual(nodes.map(\.name), ["Sources", "README.md"])
		XCTAssertEqual(nodes.first?.children.map(\.name), ["Feature", "App.swift"])
	}

	func testParseRemotesCombinesFetchAndPushURLs() {
		let output =
			"origin\thttps://example.com/Trees.git (fetch)\norigin\tgit@example.com:Trees.git (push)\n"

		let remotes = GitOutputParser.parseRemotes(output)

		XCTAssertEqual(remotes.count, 1)
		XCTAssertEqual(remotes.first?.name, "origin")
		XCTAssertEqual(remotes.first?.fetchURL, "https://example.com/Trees.git")
		XCTAssertEqual(remotes.first?.pushURL, "git@example.com:Trees.git")
	}

	func testParseRemoteBranchesSeparatesRemoteAndBranchNames() {
		let output = """
			origin/main\t1234567\t1234567890abcdef\t
			origin/feature/sidebar\t2345678\t234567890abcdef1\t
			origin/HEAD\t1234567\t1234567890abcdef\trefs/remotes/origin/main
			"""

		let branches = GitOutputParser.parseRemoteBranches(output)

		XCTAssertEqual(branches.count, 2)
		XCTAssertEqual(branches[0].remoteName, "origin")
		XCTAssertEqual(branches[0].name, "main")
		XCTAssertEqual(branches[0].fullName, "origin/main")
		XCTAssertEqual(branches[1].name, "feature/sidebar")
	}

	func testParseBranchesIncludesUpstreamTrackingCounts() {
		let output = "main\tabc1234\t*\torigin/main\tahead 2, behind 3\n"

		let branches = GitOutputParser.parseBranches(output)

		XCTAssertEqual(branches.count, 1)
		XCTAssertEqual(branches.first?.upstream, "origin/main")
		XCTAssertEqual(branches.first?.aheadCount, 2)
		XCTAssertEqual(branches.first?.behindCount, 3)
		XCTAssertEqual(branches.first?.isCurrent, true)
	}

	func testParseStashesPreservesReferenceAndMessage() {
		let output =
			"stash@{0}\u{1f}1234567890abcdef\u{1f}On main: Sidebar work\u{1f}2026-08-20 15:00:00 +0900\u{1e}"

		let stashes = GitOutputParser.parseStashes(output)

		XCTAssertEqual(stashes.count, 1)
		XCTAssertEqual(stashes.first?.reference, "stash@{0}")
		XCTAssertEqual(stashes.first?.hash, "1234567890abcdef")
		XCTAssertEqual(stashes.first?.subject, "On main: Sidebar work")
		XCTAssertNotNil(stashes.first?.date)
	}

	func testParseTagsUsesPeeledCommitForAnnotatedTags() {
		let output =
			"1.0.0\ttag0001\tcommit0001\ttagobject0001\t2026-08-20 15:00:00 +0900\tRelease\nlightweight\tcommit0002\t\tcommit0002\t2026-08-19 15:00:00 +0900\tCommit\n"

		let tags = GitOutputParser.parseTags(output)

		XCTAssertEqual(tags.count, 2)
		XCTAssertEqual(tags[0].targetHash, "commit0001")
		XCTAssertEqual(tags[1].targetHash, "commit0002")
	}

	func testRequestFileContentsReadsFileInsideRepository() async throws {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: UUID().uuidString, directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		let fileURL = repositoryURL.appending(path: "README.md")
		let expectedData = Data("Preview".utf8)
		try expectedData.write(to: fileURL)

		let data = try await LocalGitRepository().requestFileContents(
			at: "README.md",
			in: repositoryURL
		)

		XCTAssertEqual(data, expectedData)
	}

	func testRequestFileContentsRejectsPathOutsideRepository() async throws {
		let testURL = FileManager.default.temporaryDirectory
			.appending(path: UUID().uuidString, directoryHint: .isDirectory)
		let repositoryURL = testURL.appending(path: "Repository", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: testURL)
		}

		try Data("Outside".utf8).write(to: testURL.appending(path: "Outside.txt"))

		do {
			_ = try await LocalGitRepository().requestFileContents(
				at: "../Outside.txt",
				in: repositoryURL
			)
			XCTFail("Expected an invalid file path error")
		} catch GitRepositoryError.invalidFilePath {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	func testDiscardRestoresUnstagedContentWithoutChangingIndex() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "tracked.txt")
		try Data("staged".utf8).write(to: fileURL)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try Data("unstaged".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first)
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try XCTUnwrap(remainingChanges.first)
		XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "staged")
		XCTAssertTrue(remainingChange.isStaged)
		XCTAssertFalse(remainingChange.hasWorkingTreeChange)
	}

	func testDiscardDeletesUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "untracked.txt")
		try Data("untracked".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first { $0.path == "untracked.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
		XCTAssertTrue(remainingChanges.isEmpty)
	}

	func testRequestDiffReturnsAdditionForUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "untracked.txt")
		try Data("first\nsecond\n".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first { $0.path == "untracked.txt" })
		let diff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		XCTAssertTrue(diff.contains("new file mode"))
		XCTAssertTrue(diff.contains("--- /dev/null"))
		XCTAssertTrue(diff.contains("+++ b/untracked.txt"))
		XCTAssertTrue(diff.contains("+first"))
		XCTAssertTrue(diff.contains("+second"))
	}

	func testRequestDiffReturnsMetadataForEmptyUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "empty.txt")
		try Data().write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first { $0.path == "empty.txt" })
		let diff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		XCTAssertTrue(diff.contains("new file mode"))
		XCTAssertTrue(diff.contains("index 0000000..e69de29"))
	}

	func testRequestDiffSeparatesStagedAndUnstagedContentForSameFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "tracked.txt")
		try Data("staged\n".utf8).write(to: fileURL)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try Data("unstaged\n".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first)
		let stagedDiff = try await repository.requestDiff(
			for: change,
			source: .staged,
			at: repositoryURL
		)
		let unstagedDiff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		XCTAssertTrue(stagedDiff.contains("+staged"))
		XCTAssertFalse(stagedDiff.contains("+unstaged"))
		XCTAssertTrue(unstagedDiff.contains("-staged"))
		XCTAssertTrue(unstagedDiff.contains("+unstaged"))
	}

	func testRequestCommitDiffReturnsCommittedFileChanges() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try Data("updated".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Update tracked file"], at: repositoryURL)

		let repository = LocalGitRepository()
		let commits = try await repository.requestCommitHistory(at: repositoryURL)
		let commit = try XCTUnwrap(commits.first)
		let diff = try await repository.requestCommitDiff(for: commit, at: repositoryURL)

		XCTAssertTrue(diff.contains("diff --git a/tracked.txt b/tracked.txt"))
		XCTAssertTrue(diff.contains("-original"))
		XCTAssertTrue(diff.contains("+updated"))
	}

	func testRequestCommitDiffDetectsMergeFromGitObject() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let baseBranch = try requestGitOutput(
			["branch", "--show-current"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)

		try requestRunGit(["switch", "-c", "feature"], at: repositoryURL)
		try Data("feature".utf8).write(to: repositoryURL.appending(path: "feature.txt"))
		try requestRunGit(["add", "feature.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add feature"], at: repositoryURL)

		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try Data("base".utf8).write(to: repositoryURL.appending(path: "base.txt"))
		try requestRunGit(["add", "base.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Update base"], at: repositoryURL)
		try requestRunGit(["merge", "--no-ff", "feature", "-m", "Merge feature"], at: repositoryURL)

		let repository = LocalGitRepository()
		let commits = try await repository.requestCommitHistory(at: repositoryURL)
		let mergeCommit = try XCTUnwrap(commits.first { $0.parentHashes.count > 1 })
		let commitWithoutParentMetadata = GitCommit(
			hash: mergeCommit.hash,
			shortHash: mergeCommit.shortHash,
			parentHashes: [],
			author: mergeCommit.author,
			date: mergeCommit.date,
			references: mergeCommit.references,
			subject: mergeCommit.subject,
			body: mergeCommit.body
		)

		let diff = try await repository.requestCommitDiff(
			for: commitWithoutParentMetadata,
			at: repositoryURL
		)

		XCTAssertTrue(diff.contains("diff --git a/feature.txt b/feature.txt"))
		XCTAssertTrue(diff.contains("+feature"))
		XCTAssertFalse(diff.contains("base.txt"))
	}

	func testRequestCommitHistoryIncludesTagsAndExcludesInternalBackupRefs() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		try Data("internal backup".utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Internal backup commit"], at: repositoryURL)
		let internalBackupHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["reset", "--hard", "HEAD^"], at: repositoryURL)
		try requestRunGit(
			["update-ref", "refs/original/refs/heads/main", internalBackupHash],
			at: repositoryURL
		)

		try Data("tagged".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Tagged commit"], at: repositoryURL)
		let taggedHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["tag", "visible-tag", taggedHash], at: repositoryURL)
		try requestRunGit(["reset", "--hard", "HEAD^"], at: repositoryURL)

		let commits = try await LocalGitRepository().requestCommitHistory(at: repositoryURL)
		let hashes = Set(commits.map(\.hash))

		XCTAssertTrue(hashes.contains(taggedHash))
		XCTAssertFalse(hashes.contains(internalBackupHash))
	}

	func testDiscardPreservesStagedAddedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "added.txt")
		try Data("added".utf8).write(to: fileURL)
		try requestRunGit(["add", "added.txt"], at: repositoryURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first { $0.path == "added.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try XCTUnwrap(remainingChanges.first)
		XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
		XCTAssertTrue(remainingChange.isStaged)
		XCTAssertFalse(remainingChange.hasWorkingTreeChange)
	}

	func testDiscardPreservesStagedRename() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let originalFileURL = repositoryURL.appending(path: "tracked.txt")
		let renamedFileURL = repositoryURL.appending(path: "renamed.txt")
		try FileManager.default.moveItem(at: originalFileURL, to: renamedFileURL)
		try requestRunGit(["add", "--all"], at: repositoryURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first { $0.path == "renamed.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try XCTUnwrap(remainingChanges.first)
		XCTAssertFalse(FileManager.default.fileExists(atPath: originalFileURL.path))
		XCTAssertTrue(FileManager.default.fileExists(atPath: renamedFileURL.path))
		XCTAssertTrue(remainingChange.isStaged)
		XCTAssertFalse(remainingChange.hasWorkingTreeChange)
	}

	func testApplyDiffLineStagesOnlySelectedReplacement() async throws {
		let repositoryURL = try makeLineRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "tracked.txt")
		try Data("one\nTWO\nthree\nFOUR\n".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first)
		try await repository.requestApplyDiffLine(
			GitDiffLineSelection(oldLineNumber: 2, newLineNumber: 2),
			action: .stage,
			for: change,
			at: repositoryURL
		)

		let indexContents = try requestGitOutput(["show", ":tracked.txt"], at: repositoryURL)
		let workingTreeDiff = try requestGitOutput(
			["diff", "--no-color", "--", "tracked.txt"],
			at: repositoryURL
		)
		XCTAssertEqual(indexContents, "one\nTWO\nthree\nfour\n")
		XCTAssertFalse(workingTreeDiff.contains("-two"))
		XCTAssertFalse(workingTreeDiff.contains("+TWO"))
		XCTAssertTrue(workingTreeDiff.contains("-four"))
		XCTAssertTrue(workingTreeDiff.contains("+FOUR"))
	}

	func testApplyDiffLineUnstagesOnlySelectedReplacement() async throws {
		let repositoryURL = try makeLineRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "tracked.txt")
		try Data("one\nTWO\nthree\nFOUR\n".utf8).write(to: fileURL)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first)
		try await repository.requestApplyDiffLine(
			GitDiffLineSelection(oldLineNumber: 2, newLineNumber: 2),
			action: .unstage,
			for: change,
			at: repositoryURL
		)

		let indexContents = try requestGitOutput(["show", ":tracked.txt"], at: repositoryURL)
		let workingTreeDiff = try requestGitOutput(
			["diff", "--no-color", "--", "tracked.txt"],
			at: repositoryURL
		)
		XCTAssertEqual(indexContents, "one\ntwo\nthree\nFOUR\n")
		XCTAssertTrue(workingTreeDiff.contains("-two"))
		XCTAssertTrue(workingTreeDiff.contains("+TWO"))
		XCTAssertFalse(workingTreeDiff.contains("-four"))
		XCTAssertFalse(workingTreeDiff.contains("+FOUR"))
	}

	func testAmendCommitUpdatesLastCommitWithoutCreatingAnotherCommit() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}

		try await LocalGitRepository().requestCommit(
			subject: "Updated commit",
			body: "Explain the change.\n\nInclude verification details.",
			amend: true,
			at: repositoryURL
		)

		let commits = try await LocalGitRepository().requestCommitHistory(at: repositoryURL)
		let commitCount = try requestGitOutput(["rev-list", "--count", "HEAD"], at: repositoryURL)
		XCTAssertEqual(commits.first?.subject, "Updated commit")
		XCTAssertEqual(
			commits.first?.body,
			"Explain the change.\n\nInclude verification details."
		)
		XCTAssertEqual(commitCount, "1\n")
	}

	func testRequestAmendChangesAndDiffReturnsIndexedChangesFromParent() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try Data("updated".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Update tracked file"], at: repositoryURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestAmendChanges(at: repositoryURL)
		let change = try XCTUnwrap(changes.first)
		let diff = try await repository.requestAmendDiff(for: change, at: repositoryURL)

		XCTAssertEqual(change.path, "tracked.txt")
		XCTAssertEqual(change.state, .modified)
		XCTAssertTrue(diff.contains("-original"))
		XCTAssertTrue(diff.contains("+updated"))
	}

	func testUnstageFromAmendMovesChangeToWorkingTreeAndStageRestoresIt() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try Data("updated".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Update tracked file"], at: repositoryURL)
		let repository = LocalGitRepository()
		let initialAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let change = try XCTUnwrap(initialAmendChanges.first)

		try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)

		let unstagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let workingTreeChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		XCTAssertTrue(unstagedAmendChanges.isEmpty)
		XCTAssertEqual(workingTreeChanges.first?.workingTreeState, .modified)

		try await repository.requestStage(path: change.path, at: repositoryURL)

		let restagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let remainingWorkingTreeChanges = try await repository.requestWorkingTreeChanges(
			at: repositoryURL
		)
		XCTAssertEqual(restagedAmendChanges.first?.path, "tracked.txt")
		XCTAssertTrue(remainingWorkingTreeChanges.isEmpty)
	}

	func testRootCommitCanBeUnstagedAndRestagedForAmend() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let repository = LocalGitRepository()
		let initialAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let change = try XCTUnwrap(initialAmendChanges.first)

		try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)

		let unstagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let workingTreeChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		XCTAssertTrue(unstagedAmendChanges.isEmpty)
		XCTAssertEqual(workingTreeChanges.count, 1)
		XCTAssertEqual(workingTreeChanges.first?.indexState, .deleted)
		XCTAssertEqual(workingTreeChanges.first?.workingTreeState, .untracked)

		try await repository.requestStage(path: change.path, at: repositoryURL)

		let restagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		XCTAssertEqual(restagedAmendChanges.first?.state, .added)
	}

	func testRequestRemotesReturnsConfiguredRemote() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try requestRunGit(
			["remote", "add", "origin", "https://example.com/Trees.git"],
			at: repositoryURL
		)
		let head = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["update-ref", "refs/remotes/origin/main", head], at: repositoryURL)

		let remotes = try await LocalGitRepository().requestRemotes(at: repositoryURL)

		XCTAssertEqual(remotes.first?.name, "origin")
		XCTAssertEqual(remotes.first?.fetchURL, "https://example.com/Trees.git")
		XCTAssertEqual(remotes.first?.pushURL, "https://example.com/Trees.git")
		XCTAssertEqual(remotes.first?.branches.map(\.fullName), ["origin/main"])
	}

	func testCreateAndDeleteLocalBranch() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let originalBranch = try requestGitOutput(
			["branch", "--show-current"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let originalHead = try requestGitOutput(
			["rev-parse", "HEAD"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let repository = LocalGitRepository()

		try await repository.requestCreateBranch(named: "feature/local", at: repositoryURL)
		let createdBranch = try requestGitOutput(
			["branch", "--show-current"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		let createdHead = try requestGitOutput(
			["rev-parse", "HEAD"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		XCTAssertEqual(createdBranch, "feature/local")
		XCTAssertEqual(createdHead, originalHead)

		try await repository.requestSwitchBranch(named: originalBranch, at: repositoryURL)
		try await repository.requestDeleteBranch(named: "feature/local", at: repositoryURL)
		let branches = try await repository.requestBranches(at: repositoryURL)
		XCTAssertFalse(branches.contains(where: { $0.name == "feature/local" }))
	}

	func testCreateTrackingBranchFromRemoteBranch() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try requestRunGit(
			["remote", "add", "origin", "https://example.com/Trees.git"],
			at: repositoryURL
		)
		let head = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(
			["update-ref", "refs/remotes/origin/feature/remote", head],
			at: repositoryURL
		)
		let repository = LocalGitRepository()

		try await repository.requestCreateTrackingBranch(
			named: "feature/remote",
			tracking: "origin/feature/remote",
			at: repositoryURL
		)

		let branches = try await repository.requestBranches(at: repositoryURL)
		let branch = try XCTUnwrap(branches.first(where: { $0.name == "feature/remote" }))
		XCTAssertTrue(branch.isCurrent)
		XCTAssertEqual(branch.upstream, "origin/feature/remote")
	}

	func testMergeBranchCreatesMergeCommitAndPreservesBothHistories() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let baseBranch = try requestGitOutput(
			["branch", "--show-current"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["switch", "-c", "feature/merge"], at: repositoryURL)
		try Data("feature".utf8).write(to: repositoryURL.appending(path: "feature.txt"))
		try requestRunGit(["add", "feature.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Feature commit"], at: repositoryURL)
		let featureHead = try requestGitOutput(
			["rev-parse", "HEAD"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try Data("base".utf8).write(to: repositoryURL.appending(path: "base.txt"))
		try requestRunGit(["add", "base.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Base commit"], at: repositoryURL)

		try await LocalGitRepository().requestMergeBranch(
			named: "feature/merge",
			at: repositoryURL
		)

		let headParents = try requestGitOutput(
			["rev-list", "--parents", "-n", "1", "HEAD"],
			at: repositoryURL
		).split(whereSeparator: \.isWhitespace)
		XCTAssertEqual(headParents.count, 3)
		XCTAssertTrue(headParents.contains(Substring(featureHead)))
	}

	func testSetUpstreamPushAndFetchReportAheadAndBehindCounts() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesRemoteTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		let peerURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesPeerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
			try? FileManager.default.removeItem(at: peerURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		let branchName = try requestGitOutput(["branch", "--show-current"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let repository = LocalGitRepository()

		try await repository.requestPush(
			.setUpstream(remoteName: "origin", branchName: branchName),
			at: repositoryURL
		)
		try requestRunGit(["clone", "--quiet", remoteURL.path, peerURL.path], at: repositoryURL)
		try requestRunGit(["config", "user.name", "Trees Peer"], at: peerURL)
		try requestRunGit(["config", "user.email", "peer@example.com"], at: peerURL)
		try Data("remote".utf8).write(to: peerURL.appending(path: "remote.txt"))
		try requestRunGit(["add", "remote.txt"], at: peerURL)
		try requestRunGit(["commit", "--quiet", "-m", "Remote commit"], at: peerURL)
		try requestRunGit(["push", "--quiet"], at: peerURL)
		try Data("local".utf8).write(to: repositoryURL.appending(path: "local.txt"))
		try requestRunGit(["add", "local.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Local commit"], at: repositoryURL)

		try await repository.requestFetch(remote: "origin", at: repositoryURL)
		let branches = try await repository.requestBranches(at: repositoryURL)
		let currentBranch = try XCTUnwrap(branches.first(where: \.isCurrent))

		XCTAssertEqual(currentBranch.upstream, "origin/\(branchName)")
		XCTAssertEqual(currentBranch.aheadCount, 1)
		XCTAssertEqual(currentBranch.behindCount, 1)
	}

	func testForcePushWithLeaseReplacesKnownRemoteHistory() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesForcePushTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		let branchName = try requestGitOutput(["branch", "--show-current"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let repository = LocalGitRepository()
		try await repository.requestPush(
			.setUpstream(remoteName: "origin", branchName: branchName),
			at: repositoryURL
		)

		try Data("remote history".utf8).write(to: repositoryURL.appending(path: "history.txt"))
		try requestRunGit(["add", "history.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Remote history"], at: repositoryURL)
		try await repository.requestPush(.upstream, at: repositoryURL)
		try requestRunGit(["reset", "--hard", "HEAD^"], at: repositoryURL)
		try Data("replacement".utf8).write(to: repositoryURL.appending(path: "replacement.txt"))
		try requestRunGit(["add", "replacement.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Replacement history"], at: repositoryURL)

		try await repository.requestForcePush(.upstream, at: repositoryURL)

		let localHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let remoteHash = try requestGitOutput(
			["--git-dir", remoteURL.path, "rev-parse", "refs/heads/\(branchName)"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		XCTAssertEqual(remoteHash, localHash)
	}

	func testPushTagsPublishesLocalTagsToRemote() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesPushTagsTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		try requestRunGit(["tag", "release/1.0.0"], at: repositoryURL)

		try await LocalGitRepository().requestPushTags(remote: "origin", at: repositoryURL)

		let localHash = try requestGitOutput(["rev-parse", "release/1.0.0"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let remoteHash = try requestGitOutput(
			["--git-dir", remoteURL.path, "rev-parse", "refs/tags/release/1.0.0"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)
		XCTAssertEqual(remoteHash, localHash)
	}

	func testFetchAllUpdatesRemoteTrackingReferences() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesFetchAllTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		let peerURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesFetchAllPeer-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
			try? FileManager.default.removeItem(at: peerURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		let branchName = try requestGitOutput(["branch", "--show-current"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let repository = LocalGitRepository()
		try await repository.requestPush(
			.setUpstream(remoteName: "origin", branchName: branchName),
			at: repositoryURL
		)
		try requestRunGit(["clone", "--quiet", remoteURL.path, peerURL.path], at: repositoryURL)
		try requestRunGit(["config", "user.name", "Trees Peer"], at: peerURL)
		try requestRunGit(["config", "user.email", "peer@example.com"], at: peerURL)
		try Data("remote".utf8).write(to: peerURL.appending(path: "remote.txt"))
		try requestRunGit(["add", "remote.txt"], at: peerURL)
		try requestRunGit(["commit", "--quiet", "-m", "Remote commit"], at: peerURL)
		try requestRunGit(["push", "--quiet"], at: peerURL)
		let expectedHash = try requestGitOutput(["rev-parse", "HEAD"], at: peerURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		try await repository.requestFetchAll(at: repositoryURL)
		let fetchedHash = try requestGitOutput(
			["rev-parse", "refs/remotes/origin/\(branchName)"],
			at: repositoryURL
		).trimmingCharacters(in: .whitespacesAndNewlines)

		XCTAssertEqual(fetchedHash, expectedHash)
	}

	func testRequestOperationStateReportsNormalAndDetachedHead() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let repository = LocalGitRepository()

		let normalState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertEqual(normalState, .normal)
		try requestRunGit(["switch", "--detach"], at: repositoryURL)
		let detachedState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertEqual(detachedState, .detachedHead)
	}

	func testMergeBranchReturnsConflictedOperationState() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let baseBranch = try requestGitOutput(["branch", "--show-current"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["switch", "-c", "conflict"], at: repositoryURL)
		try Data("branch".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Branch change"], at: repositoryURL)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try Data("base".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Base change"], at: repositoryURL)

		let repository = LocalGitRepository()
		try await repository.requestMergeBranch(named: "conflict", at: repositoryURL)
		let operationState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertEqual(operationState.operation?.kind, .merge)
		XCTAssertEqual(operationState.conflicts.count, 1)
		XCTAssertEqual(operationState.conflicts.first?.kind, .bothModified)
		XCTAssertEqual(operationState.conflicts.first?.path, "tracked.txt")
	}

	func testCreateTagTargetsSpecifiedHistoricalCommit() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let historicalHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try Data("updated".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Update tracked file"], at: repositoryURL)
		let headHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let repository = LocalGitRepository()

		try await repository.requestCreateTag(
			named: "historical-tag",
			message: "",
			commitHash: historicalHash,
			at: repositoryURL
		)
		let tags = try await repository.requestTags(at: repositoryURL)

		XCTAssertNotEqual(historicalHash, headHash)
		XCTAssertEqual(tags.first(where: { $0.name == "historical-tag" })?.targetHash, historicalHash)
	}

	func testDeleteTagRemovesLocalTag() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try requestRunGit(["tag", "release/1.0.0"], at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestDeleteTag(named: "release/1.0.0", at: repositoryURL)

		let tags = try await repository.requestTags(at: repositoryURL)
		XCTAssertFalse(tags.contains(where: { $0.name == "release/1.0.0" }))
	}

	func testCreateAndDropStashIncludesUntrackedFiles() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try Data("stashed".utf8).write(to: repositoryURL.appending(path: "untracked.txt"))
		let repository = LocalGitRepository()

		try await repository.requestCreateStash(message: "Sidebar work", at: repositoryURL)

		let stashes = try await repository.requestStashes(at: repositoryURL)
		let stash = try XCTUnwrap(stashes.first)
		XCTAssertTrue(stash.subject.contains("Sidebar work"))
		XCTAssertFalse(
			FileManager.default.fileExists(
				atPath: repositoryURL.appending(path: "untracked.txt").path
			)
		)

		try await repository.requestApplyStash(stash, at: repositoryURL)
		XCTAssertTrue(
			FileManager.default.fileExists(
				atPath: repositoryURL.appending(path: "untracked.txt").path
			)
		)

		try await repository.requestDropStash(stash, at: repositoryURL)
		let remainingStashes = try await repository.requestStashes(at: repositoryURL)
		XCTAssertTrue(remainingStashes.isEmpty)
	}

	func testMergeConflictCanBeResolvedContinuedAndRestoredByNewRepositoryInstance() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let baseBranch = try currentBranch(at: repositoryURL)
		try requestRunGit(["switch", "-c", "conflict"], at: repositoryURL)
		try commit(contents: "incoming", message: "Incoming change", at: repositoryURL)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try commit(contents: "current", message: "Current change", at: repositoryURL)

		try await LocalGitRepository().requestMergeBranch(named: "conflict", at: repositoryURL)
		let restoredState = try await LocalGitRepository().requestOperationState(at: repositoryURL)
		let conflict = try XCTUnwrap(restoredState.conflicts.first)
		XCTAssertEqual(restoredState.operation?.kind, .merge)

		let repository = LocalGitRepository()
		try await repository.requestResolveConflict(conflict, using: .theirs, at: repositoryURL)
		let resolvedState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertTrue(resolvedState.conflicts.isEmpty)
		XCTAssertEqual(resolvedState.operation?.kind, .merge)
		try await repository.requestPerformOperationAction(.continue, for: .merge, at: repositoryURL)

		let completedState = try await repository.requestOperationState(at: repositoryURL)
		let contents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		XCTAssertTrue(completedState.isIdle)
		XCTAssertEqual(contents, "incoming")
	}

	func testRebaseConflictCanBeAborted() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let baseBranch = try currentBranch(at: repositoryURL)
		try requestRunGit(["switch", "-c", "feature"], at: repositoryURL)
		try commit(contents: "feature", message: "Feature change", at: repositoryURL)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try commit(contents: "base", message: "Base change", at: repositoryURL)
		try requestRunGit(["switch", "feature"], at: repositoryURL)

		let repository = LocalGitRepository()
		try await repository.requestRebase(onto: baseBranch, at: repositoryURL)
		let activeState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertEqual(activeState.operation?.kind, .rebase)
		XCTAssertTrue(activeState.hasConflicts)
		try await repository.requestPerformOperationAction(.abort, for: .rebase, at: repositoryURL)

		let completedState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertTrue(completedState.isIdle)
		XCTAssertEqual(try currentBranch(at: repositoryURL), "feature")
	}

	func testRebaseConflictCanBeResolvedAndContinuedWithoutEditorPrompt() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let baseBranch = try currentBranch(at: repositoryURL)
		try requestRunGit(["switch", "-c", "feature"], at: repositoryURL)
		try commit(contents: "feature", message: "Feature change", at: repositoryURL)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try commit(contents: "base", message: "Base change", at: repositoryURL)
		try requestRunGit(["switch", "feature"], at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestRebase(onto: baseBranch, at: repositoryURL)
		let conflictedState = try await repository.requestOperationState(at: repositoryURL)
		let conflict = try XCTUnwrap(conflictedState.conflicts.first)
		try await repository.requestResolveConflict(conflict, using: .theirs, at: repositoryURL)
		try await repository.requestPerformOperationAction(.continue, for: .rebase, at: repositoryURL)

		let state = try await repository.requestOperationState(at: repositoryURL)
		let contents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		XCTAssertTrue(state.isIdle)
		XCTAssertEqual(try currentBranch(at: repositoryURL), "feature")
		XCTAssertEqual(contents, "feature")
	}

	func testRebaseConflictCanSkipCurrentCommit() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let baseBranch = try currentBranch(at: repositoryURL)
		try requestRunGit(["switch", "-c", "feature"], at: repositoryURL)
		try commit(contents: "feature", message: "Feature change", at: repositoryURL)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)
		try commit(contents: "base", message: "Base change", at: repositoryURL)
		try requestRunGit(["switch", "feature"], at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestRebase(onto: baseBranch, at: repositoryURL)
		try await repository.requestPerformOperationAction(.skip, for: .rebase, at: repositoryURL)

		let state = try await repository.requestOperationState(at: repositoryURL)
		let contents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		XCTAssertTrue(state.isIdle)
		XCTAssertEqual(contents, "base")
	}

	func testCherryPickAndRevertCompleteWithoutLeavingOperationState() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let baseBranch = try currentBranch(at: repositoryURL)
		try requestRunGit(["switch", "-c", "feature"], at: repositoryURL)
		try Data("picked".utf8).write(to: repositoryURL.appending(path: "picked.txt"))
		try requestRunGit(["add", "picked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Picked commit"], at: repositoryURL)
		let pickedHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try requestRunGit(["switch", baseBranch], at: repositoryURL)

		let repository = LocalGitRepository()
		try await repository.requestCherryPick(
			commitHash: pickedHash,
			mainline: nil,
			at: repositoryURL
		)
		XCTAssertTrue(
			FileManager.default.fileExists(atPath: repositoryURL.appending(path: "picked.txt").path))
		let cherryPickState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertTrue(cherryPickState.isIdle)

		try await repository.requestRevert(commitHash: pickedHash, mainline: nil, at: repositoryURL)
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: repositoryURL.appending(path: "picked.txt").path))
		let revertState = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertTrue(revertState.isIdle)
	}

	func testResetModesPreserveUntrackedFiles() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let initialHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try commit(contents: "updated", message: "Update tracked", at: repositoryURL)
		let updatedHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let untrackedURL = repositoryURL.appending(path: "untracked.txt")
		try Data("keep".utf8).write(to: untrackedURL)
		let repository = LocalGitRepository()

		try await repository.requestReset(to: initialHash, mode: .soft, at: repositoryURL)
		XCTAssertFalse(
			try requestGitOutput(["diff", "--cached", "--name-only"], at: repositoryURL).isEmpty)
		try await repository.requestReset(to: updatedHash, mode: .hard, at: repositoryURL)
		try commit(contents: "mixed", message: "Mixed source", at: repositoryURL)
		try await repository.requestReset(to: updatedHash, mode: .mixed, at: repositoryURL)
		XCTAssertFalse(try requestGitOutput(["diff", "--name-only"], at: repositoryURL).isEmpty)
		try await repository.requestReset(to: updatedHash, mode: .hard, at: repositoryURL)

		XCTAssertTrue(FileManager.default.fileExists(atPath: untrackedURL.path))
		XCTAssertEqual(
			try String(
				contentsOf: repositoryURL.appending(path: "tracked.txt"),
				encoding: .utf8
			),
			"updated"
		)
	}

	func testStashPreviewAndIncludeUntrackedOption() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let untrackedURL = repositoryURL.appending(path: "untracked.txt")
		try Data("changed".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try Data("untracked".utf8).write(to: untrackedURL)
		let repository = LocalGitRepository()

		try await repository.requestCreateStash(
			message: "Tracked only",
			includeUntracked: false,
			at: repositoryURL
		)
		let trackedOnlyStashes = try await repository.requestStashes(at: repositoryURL)
		let trackedOnly = try XCTUnwrap(trackedOnlyStashes.first)
		let trackedDiff = try await repository.requestStashDiff(for: trackedOnly, at: repositoryURL)
		XCTAssertTrue(trackedDiff.contains("tracked.txt"))
		XCTAssertFalse(trackedDiff.contains("untracked.txt"))
		XCTAssertTrue(FileManager.default.fileExists(atPath: untrackedURL.path))
		try await repository.requestDropStash(trackedOnly, at: repositoryURL)

		try Data("changed again".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try await repository.requestCreateStash(
			message: "Everything",
			includeUntracked: true,
			at: repositoryURL
		)
		let everythingStashes = try await repository.requestStashes(at: repositoryURL)
		let everything = try XCTUnwrap(everythingStashes.first)
		let everythingDiff = try await repository.requestStashDiff(for: everything, at: repositoryURL)
		XCTAssertTrue(everythingDiff.contains("untracked.txt"))
		XCTAssertFalse(FileManager.default.fileExists(atPath: untrackedURL.path))
	}

	func testStashApplyConflictHasNoPersistentOperationActions() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let repository = LocalGitRepository()
		try Data("stashed".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try await repository.requestCreateStash(
			message: "Conflicting stash",
			includeUntracked: true,
			at: repositoryURL
		)
		try commit(contents: "current", message: "Current change", at: repositoryURL)
		let stashes = try await repository.requestStashes(at: repositoryURL)
		let stash = try XCTUnwrap(stashes.first)

		try await repository.requestApplyStash(stash, at: repositoryURL)

		let state = try await repository.requestOperationState(at: repositoryURL)
		XCTAssertTrue(state.hasConflicts)
		XCTAssertNil(state.operation)
	}

	func testRemoteBranchDeleteRemovesBranchFromRemote() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesRemoteDelete-\(UUID().uuidString).git")
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		try requestRunGit(["switch", "-c", "cleanup"], at: repositoryURL)
		try requestRunGit(["push", "--quiet", "-u", "origin", "cleanup"], at: repositoryURL)
		let repository = LocalGitRepository()
		let remotes = try await repository.requestRemotes(at: repositoryURL)
		let remote = try XCTUnwrap(remotes.first)
		let branch = try XCTUnwrap(remote.branches.first { $0.name == "cleanup" })

		try await repository.requestDeleteRemoteBranch(branch, at: repositoryURL)

		let heads = try requestGitOutput(
			["ls-remote", "--heads", remoteURL.path, "refs/heads/cleanup"],
			at: repositoryURL
		)
		XCTAssertTrue(heads.isEmpty)
	}

	func testBranchRenameAndRemoteCRUD() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let originalBranch = try currentBranch(at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestRenameBranch(
			named: originalBranch,
			to: "renamed",
			at: repositoryURL
		)
		XCTAssertEqual(try currentBranch(at: repositoryURL), "renamed")

		try await repository.requestAddRemote(
			named: "origin",
			fetchURL: "https://example.com/fetch.git",
			pushURL: "ssh://example.com/push.git",
			at: repositoryURL
		)
		var remotes = try await repository.requestRemotes(at: repositoryURL)
		var remote = try XCTUnwrap(remotes.first)
		XCTAssertEqual(remote.fetchURL, "https://example.com/fetch.git")
		XCTAssertEqual(remote.pushURL, "ssh://example.com/push.git")

		try await repository.requestUpdateRemote(
			named: "origin",
			fetchURL: "https://example.com/updated.git",
			pushURL: nil,
			at: repositoryURL
		)
		try await repository.requestRenameRemote(named: "origin", to: "upstream", at: repositoryURL)
		remotes = try await repository.requestRemotes(at: repositoryURL)
		remote = try XCTUnwrap(remotes.first)
		XCTAssertEqual(remote.name, "upstream")
		XCTAssertEqual(remote.fetchURL, "https://example.com/updated.git")
		XCTAssertEqual(remote.pushURL, "https://example.com/updated.git")

		try await repository.requestDeleteRemote(named: "upstream", at: repositoryURL)
		remotes = try await repository.requestRemotes(at: repositoryURL)
		XCTAssertTrue(remotes.isEmpty)
	}

	func testCommitMetadataAndNoEditAmend() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		try requestRunGit(["config", "user.name", "Committer Name"], at: repositoryURL)
		try requestRunGit(["config", "user.email", "committer@example.com"], at: repositoryURL)
		try Data("metadata".utf8).write(to: repositoryURL.appending(path: "metadata.txt"))
		try requestRunGit(["add", "metadata.txt"], at: repositoryURL)
		try requestRunGit(
			["commit", "--quiet", "--author", "Author Name <author@example.com>", "-m", "Metadata"],
			at: repositoryURL
		)
		let repository = LocalGitRepository()
		var commits = try await repository.requestCommitHistory(at: repositoryURL)
		let commit = try XCTUnwrap(commits.first)
		XCTAssertEqual(commit.author, "Author Name")
		XCTAssertEqual(commit.authorEmail, "author@example.com")
		XCTAssertEqual(commit.committer, "Committer Name")
		XCTAssertEqual(commit.committerEmail, "committer@example.com")
		XCTAssertGreaterThan(commit.committedDate.timeIntervalSince1970, 0)

		try Data("amended".utf8).write(to: repositoryURL.appending(path: "metadata.txt"))
		try requestRunGit(["add", "metadata.txt"], at: repositoryURL)
		try await repository.requestAmendWithoutEditingMessage(at: repositoryURL)
		commits = try await repository.requestCommitHistory(at: repositoryURL)
		let amended = try XCTUnwrap(commits.first)
		XCTAssertEqual(amended.subject, "Metadata")
		XCTAssertEqual(try requestGitOutput(["rev-list", "--count", "HEAD"], at: repositoryURL), "2\n")
	}

	private func makeRepository() throws -> URL {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesDiscardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		try requestRunGit(["init", "--quiet"], at: repositoryURL)
		try requestRunGit(["config", "user.name", "Trees Tests"], at: repositoryURL)
		try requestRunGit(["config", "user.email", "trees@example.com"], at: repositoryURL)
		try Data("original".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Initial commit"], at: repositoryURL)
		return repositoryURL
	}

	private func currentBranch(at repositoryURL: URL) throws -> String {
		try requestGitOutput(["branch", "--show-current"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func commit(contents: String, message: String, at repositoryURL: URL) throws {
		try Data(contents.utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", message], at: repositoryURL)
	}

	private func makeLineRepository() throws -> URL {
		let repositoryURL = try makeRepository()
		try Data("one\ntwo\nthree\nfour\n".utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add line fixture"], at: repositoryURL)
		return repositoryURL
	}

	private func requestRunGit(_ arguments: [String], at repositoryURL: URL) throws {
		_ = try requestGitOutput(arguments, at: repositoryURL)
	}

	private func requestGitOutput(_ arguments: [String], at repositoryURL: URL) throws -> String {
		let standardOutput = Pipe()
		let standardError = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", repositoryURL.path] + arguments
		process.standardOutput = standardOutput
		process.standardError = standardError
		try process.run()
		process.waitUntilExit()

		guard process.terminationStatus == 0 else {
			let data = standardError.fileHandleForReading.readDataToEndOfFile()
			let message = String(decoding: data, as: UTF8.self)
			throw NSError(
				domain: "GitOutputParserTests",
				code: Int(process.terminationStatus),
				userInfo: [NSLocalizedDescriptionKey: message]
			)
		}

		let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
		return String(decoding: data, as: UTF8.self)
	}
}
