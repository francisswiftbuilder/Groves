import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitOutputParserTests {
	@Test
	func testCloneRepositoryCreatesRepositoryInSelectedDirectory() async throws {
		let sourceRepositoryURL = try makeRepository()
		let destinationDirectoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesCloneTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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

		#expect(clonedRepositoryURL.lastPathComponent == sourceRepositoryURL.lastPathComponent)
		#expect(
			FileManager.default.fileExists(atPath: clonedRepositoryURL.appending(path: ".git").path))
	}

	@Test
	func testParseWorkingTreeChangesSeparatesIndexAndWorkingTreeStates() {
		let output = "M  staged.swift\0 M unstaged.swift\0?? new.swift\0"

		let changes = GitOutputParser.parseWorkingTreeChanges(output)

		#expect(changes.count == 3)
		#expect(changes.first(where: { $0.path == "staged.swift" })?.indexState == .modified)
		#expect(changes.first(where: { $0.path == "unstaged.swift" })?.workingTreeState == .modified)
		#expect(changes.first(where: { $0.path == "new.swift" })?.workingTreeState == .untracked)
	}

	@Test
	func testParseWorkingTreeChangesMergesDuplicateDeletedAndUntrackedPath() {
		let output = "D  tracked.txt\0?? tracked.txt\0"

		let changes = GitOutputParser.parseWorkingTreeChanges(output)

		#expect(changes.count == 1)
		#expect(changes.first?.path == "tracked.txt")
		#expect(changes.first?.indexState == .deleted)
		#expect(changes.first?.workingTreeState == .untracked)
	}

	@Test
	func testParseConflictsPreservesKindsAndStageAvailability() {
		let zeroHash = String(repeating: "0", count: 40)
		let objectHash = String(repeating: "1", count: 40)
		let records = GitConflictKind.allCases.enumerated().map { index, kind in
			"u \(kind.rawValue) N... 100644 100644 100644 100644 \(index == 0 ? zeroHash : objectHash) \(objectHash) \(index == 1 ? zeroHash : objectHash) conflict-\(index).txt"
		}

		let conflicts = GitOutputParser.parseConflicts(records.joined(separator: "\0") + "\0")

		#expect(Set(conflicts.map(\.kind)) == Set(GitConflictKind.allCases))
		#expect(conflicts.first(where: { $0.path == "conflict-0.txt" })?.hasBase == false)
		#expect(conflicts.first(where: { $0.path == "conflict-1.txt" })?.hasTheirs == false)
		#expect(conflicts.allSatisfy { $0.hasOurs })
	}

	@Test
	func testParseAmendChangesPreservesRenamePaths() {
		let output = "M\0Sources/App.swift\0R100\0Old.swift\0New.swift\0"

		let changes = GitOutputParser.parseAmendChanges(output)

		#expect(changes.count == 2)
		#expect(changes.first(where: { $0.path == "Sources/App.swift" })?.state == .modified)
		#expect(changes.first(where: { $0.path == "New.swift" })?.state == .renamed)
		#expect(changes.first(where: { $0.path == "New.swift" })?.previousPath == "Old.swift")
	}

	@Test
	func testBuildFileTreeGroupsFilesByDirectory() {
		let nodes = GitOutputParser.buildFileTree(
			paths: ["Sources/App.swift", "Sources/Feature/View.swift", "README.md"]
		)

		#expect(nodes.map(\.name) == ["Sources", "README.md"])
		#expect(nodes.first?.children.map(\.name) == ["Feature", "App.swift"])
	}

	@Test
	func testParseBranchesIncludesUpstreamTrackingCounts() {
		let output = "main\tabc1234\t*\torigin/main\tahead 2, behind 3\n"

		let branches = GitOutputParser.parseBranches(output)

		#expect(branches.count == 1)
		#expect(branches.first?.upstream == "origin/main")
		#expect(branches.first?.aheadCount == 2)
		#expect(branches.first?.behindCount == 3)
		#expect(branches.first?.isCurrent == true)
	}

	@Test
	func testParseStashesPreservesReferenceAndMessage() {
		let output =
			"stash@{0}\u{1f}1234567890abcdef\u{1f}On main: Sidebar work\u{1f}2026-08-20 15:00:00 +0900\u{1e}"

		let stashes = GitOutputParser.parseStashes(output)

		#expect(stashes.count == 1)
		#expect(stashes.first?.reference == "stash@{0}")
		#expect(stashes.first?.hash == "1234567890abcdef")
		#expect(stashes.first?.subject == "On main: Sidebar work")
		#expect(stashes.first?.date != nil)
	}

	@Test
	func testParseTagsUsesPeeledCommitForAnnotatedTags() {
		let output =
			"1.0.0\ttag0001\tcommit0001\ttagobject0001\t2026-08-20 15:00:00 +0900\tRelease\nlightweight\tcommit0002\t\tcommit0002\t2026-08-19 15:00:00 +0900\tCommit\n"

		let tags = GitOutputParser.parseTags(output)

		#expect(tags.count == 2)
		#expect(tags[0].targetHash == "commit0001")
		#expect(tags[1].targetHash == "commit0002")
	}

	@Test
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

		#expect(data == expectedData)
	}

	@Test
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
			Issue.record("Expected an invalid file path error")
		} catch GitRepositoryError.invalidFilePath {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test
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
		let change = try #require(changes.first)
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try #require(remainingChanges.first)
		#expect(try String(contentsOf: fileURL, encoding: .utf8) == "staged")
		#expect(remainingChange.isStaged)
		#expect(!(remainingChange.hasWorkingTreeChange))
	}

	@Test
	func testDiscardDeletesUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "untracked.txt")
		try Data("untracked".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first { $0.path == "untracked.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		#expect(!(FileManager.default.fileExists(atPath: fileURL.path)))
		#expect(remainingChanges.isEmpty)
	}

	@Test
	func testRequestDiffReturnsAdditionForUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "untracked.txt")
		try Data("first\nsecond\n".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first { $0.path == "untracked.txt" })
		let diff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		#expect(diff.contains("new file mode"))
		#expect(diff.contains("--- /dev/null"))
		#expect(diff.contains("+++ b/untracked.txt"))
		#expect(diff.contains("+first"))
		#expect(diff.contains("+second"))
	}

	@Test
	func testRequestDiffReturnsMetadataForEmptyUntrackedFile() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "empty.txt")
		try Data().write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first { $0.path == "empty.txt" })
		let diff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		#expect(diff.contains("new file mode"))
		#expect(diff.contains("index 0000000..e69de29"))
	}

	@Test
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
		let change = try #require(changes.first)
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

		#expect(stagedDiff.contains("+staged"))
		#expect(!(stagedDiff.contains("+unstaged")))
		#expect(unstagedDiff.contains("-staged"))
		#expect(unstagedDiff.contains("+unstaged"))
	}

	@Test
	func testRequestImageDiffSeparatesHeadIndexAndWorkingTreeData() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "preview.png")
		let originalData = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
		let stagedData = Data([0x89, 0x50, 0x4E, 0x47, 0x02])
		let workingTreeData = Data([0x89, 0x50, 0x4E, 0x47, 0x03])
		try originalData.write(to: fileURL)
		try requestRunGit(["add", "preview.png"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add preview"], at: repositoryURL)
		try stagedData.write(to: fileURL)
		try requestRunGit(["add", "preview.png"], at: repositoryURL)
		try workingTreeData.write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first { $0.path == "preview.png" })
		let stagedDiff = try await repository.requestImageDiff(
			for: change,
			source: .staged,
			at: repositoryURL
		)
		let unstagedDiff = try await repository.requestImageDiff(
			for: change,
			source: .unstaged,
			at: repositoryURL
		)

		#expect(stagedDiff.before == originalData)
		#expect(stagedDiff.after == stagedData)
		#expect(unstagedDiff.before == stagedData)
		#expect(unstagedDiff.after == workingTreeData)
	}

	@Test
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
		let commit = try #require(commits.first)
		let diff = try await repository.requestCommitDiff(for: commit, at: repositoryURL)

		#expect(diff.contains("diff --git a/tracked.txt b/tracked.txt"))
		#expect(diff.contains("-original"))
		#expect(diff.contains("+updated"))
	}

	@Test
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
		let mergeCommit = try #require(commits.first { $0.parentHashes.count > 1 })
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

		#expect(diff.contains("diff --git a/feature.txt b/feature.txt"))
		#expect(diff.contains("+feature"))
		#expect(!(diff.contains("base.txt")))
	}

	@Test
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

		#expect(hashes.contains(taggedHash))
		#expect(!(hashes.contains(internalBackupHash)))
	}

	@Test
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
		let change = try #require(changes.first { $0.path == "added.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try #require(remainingChanges.first)
		#expect(FileManager.default.fileExists(atPath: fileURL.path))
		#expect(remainingChange.isStaged)
		#expect(!(remainingChange.hasWorkingTreeChange))
	}

	@Test
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
		let change = try #require(changes.first { $0.path == "renamed.txt" })
		try await repository.requestDiscard(change: change, at: repositoryURL)

		let remainingChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let remainingChange = try #require(remainingChanges.first)
		#expect(!(FileManager.default.fileExists(atPath: originalFileURL.path)))
		#expect(FileManager.default.fileExists(atPath: renamedFileURL.path))
		#expect(remainingChange.isStaged)
		#expect(!(remainingChange.hasWorkingTreeChange))
	}

	@Test
	func testApplyDiffLineStagesOnlySelectedReplacement() async throws {
		let repositoryURL = try makeLineRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "tracked.txt")
		try Data("one\nTWO\nthree\nFOUR\n".utf8).write(to: fileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first)
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
		#expect(indexContents == "one\nTWO\nthree\nfour\n")
		#expect(!(workingTreeDiff.contains("-two")))
		#expect(!(workingTreeDiff.contains("+TWO")))
		#expect(workingTreeDiff.contains("-four"))
		#expect(workingTreeDiff.contains("+FOUR"))
	}

	@Test
	func testWorkingTreeChangesRelatedToChangeOnlyReadsSelectedPaths() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let otherFileURL = repositoryURL.appending(path: "other.txt")
		try Data("original".utf8).write(to: otherFileURL)
		try requestRunGit(["add", "other.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add another file"], at: repositoryURL)

		try Data("tracked change".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try Data("other change".utf8).write(to: otherFileURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let trackedChange = try #require(changes.first { $0.path == "tracked.txt" })
		let relatedChanges = try await repository.requestWorkingTreeChanges(
			relatedTo: trackedChange,
			at: repositoryURL
		)

		#expect(relatedChanges.map(\.path) == ["tracked.txt"])
	}

	@Test
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
		let change = try #require(changes.first)
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
		#expect(indexContents == "one\ntwo\nthree\nFOUR\n")
		#expect(workingTreeDiff.contains("-two"))
		#expect(workingTreeDiff.contains("+TWO"))
		#expect(!(workingTreeDiff.contains("-four")))
		#expect(!(workingTreeDiff.contains("+FOUR")))
	}

	@Test
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
		#expect(commits.first?.subject == "Updated commit")
		#expect(commits.first?.body == "Explain the change.\n\nInclude verification details.")
		#expect(commitCount == "1\n")
	}

	@Test
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
		let change = try #require(changes.first)
		let diff = try await repository.requestAmendDiff(for: change, at: repositoryURL)

		#expect(change.path == "tracked.txt")
		#expect(change.state == .modified)
		#expect(diff.contains("-original"))
		#expect(diff.contains("+updated"))
	}

	@Test
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
		let change = try #require(initialAmendChanges.first)

		try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)

		let unstagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let workingTreeChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		#expect(unstagedAmendChanges.isEmpty)
		#expect(workingTreeChanges.first?.workingTreeState == .modified)

		try await repository.requestStage(path: change.path, at: repositoryURL)

		let restagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let remainingWorkingTreeChanges = try await repository.requestWorkingTreeChanges(
			at: repositoryURL
		)
		#expect(restagedAmendChanges.first?.path == "tracked.txt")
		#expect(remainingWorkingTreeChanges.isEmpty)
	}

	@Test
	func testRootCommitCanBeUnstagedAndRestagedForAmend() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let repository = LocalGitRepository()
		let initialAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let change = try #require(initialAmendChanges.first)

		try await repository.requestUnstageFromAmend(change: change, at: repositoryURL)

		let unstagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		let workingTreeChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		#expect(unstagedAmendChanges.isEmpty)
		#expect(workingTreeChanges.count == 1)
		#expect(workingTreeChanges.first?.indexState == .deleted)
		#expect(workingTreeChanges.first?.workingTreeState == .untracked)

		try await repository.requestStage(path: change.path, at: repositoryURL)

		let restagedAmendChanges = try await repository.requestAmendChanges(at: repositoryURL)
		#expect(restagedAmendChanges.first?.state == .added)
	}

	@Test
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
		#expect(createdBranch == "feature/local")
		#expect(createdHead == originalHead)

		try await repository.requestSwitchBranch(named: originalBranch, at: repositoryURL)
		try await repository.requestDeleteBranch(named: "feature/local", at: repositoryURL)
		let branches = try await repository.requestBranches(at: repositoryURL)
		#expect(!(branches.contains(where: { $0.name == "feature/local" })))
	}

	@Test
	func testCreateBranchFromCommitAndCheckoutDetachedCommit() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let originalBranch = try currentBranch(at: repositoryURL)
		let originalCommit = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try Data("second".utf8).write(to: repositoryURL.appending(path: "second.txt"))
		try requestRunGit(["add", "second.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Second commit"], at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestCreateBranch(
			named: "release/initial",
			from: originalCommit,
			at: repositoryURL
		)
		#expect(try currentBranch(at: repositoryURL) == "release/initial")
		#expect(
			try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
				.trimmingCharacters(in: .whitespacesAndNewlines) == originalCommit)

		try await repository.requestSwitchBranch(named: originalBranch, at: repositoryURL)
		try await repository.requestCheckoutCommit(originalCommit, at: repositoryURL)
		let operationState = try await repository.requestOperationState(at: repositoryURL)
		#expect(operationState.isDetached)
	}

	@Test
	func testCreateTrackingBranchFromRemoteBranch() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try requestRunGit(
			["remote", "add", "origin", "https://example.com/Groves.git"],
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
		let branch = try #require(branches.first(where: { $0.name == "feature/remote" }))
		#expect(branch.isCurrent)
		#expect(branch.upstream == "origin/feature/remote")
	}

	@Test
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
		#expect(headParents.count == 3)
		#expect(headParents.contains(Substring(featureHead)))
	}

	@Test
	func testSetUpstreamPushAndFetchReportAheadAndBehindCounts() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesRemoteTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		let peerURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesPeerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
		try requestRunGit(["config", "user.name", "Groves Peer"], at: peerURL)
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
		let currentBranch = try #require(branches.first { $0.isCurrent })

		#expect(currentBranch.upstream == "origin/\(branchName)")
		#expect(currentBranch.aheadCount == 1)
		#expect(currentBranch.behindCount == 1)
	}

	@Test
	func testPreparePullHandlesUpToDateAheadFastForwardAndDivergence() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesPullTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		let peerURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesPullPeer-\(UUID().uuidString)", directoryHint: .isDirectory)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
			try? FileManager.default.removeItem(at: remoteURL)
			try? FileManager.default.removeItem(at: peerURL)
		}
		try requestRunGit(["init", "--quiet", "--bare", remoteURL.path], at: repositoryURL)
		try requestRunGit(["remote", "add", "origin", remoteURL.path], at: repositoryURL)
		let branchName = try currentBranch(at: repositoryURL)
		let repository = LocalGitRepository()
		try await repository.requestPush(
			.setUpstream(remoteName: "origin", branchName: branchName),
			at: repositoryURL
		)

		let upToDateOutcome = try await repository.requestPreparePull(at: repositoryURL)
		#expect(upToDateOutcome == .upToDate)

		try Data("local-ahead".utf8).write(to: repositoryURL.appending(path: "local-ahead.txt"))
		try requestRunGit(["add", "local-ahead.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Local ahead"], at: repositoryURL)
		let aheadOutcome = try await repository.requestPreparePull(at: repositoryURL)
		#expect(aheadOutcome == .aheadOnly(aheadCount: 1))
		try await repository.requestPush(.upstream, at: repositoryURL)

		try requestRunGit(["clone", "--quiet", remoteURL.path, peerURL.path], at: repositoryURL)
		try requestRunGit(["config", "user.name", "Groves Peer"], at: peerURL)
		try requestRunGit(["config", "user.email", "peer@example.com"], at: peerURL)
		try Data("remote-behind".utf8).write(to: peerURL.appending(path: "remote-behind.txt"))
		try requestRunGit(["add", "remote-behind.txt"], at: peerURL)
		try requestRunGit(["commit", "--quiet", "-m", "Remote behind"], at: peerURL)
		try requestRunGit(["push", "--quiet"], at: peerURL)
		let fastForwardOutcome = try await repository.requestPreparePull(at: repositoryURL)
		#expect(fastForwardOutcome == .fastForwarded)

		try Data("local-diverged".utf8).write(
			to: repositoryURL.appending(path: "local-diverged.txt")
		)
		try requestRunGit(["add", "local-diverged.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Local diverged"], at: repositoryURL)
		try Data("remote-diverged".utf8).write(
			to: peerURL.appending(path: "remote-diverged.txt")
		)
		try requestRunGit(["add", "remote-diverged.txt"], at: peerURL)
		try requestRunGit(["commit", "--quiet", "-m", "Remote diverged"], at: peerURL)
		try requestRunGit(["push", "--quiet"], at: peerURL)

		guard
			case .diverged(let divergence) = try await repository.requestPreparePull(
				at: repositoryURL
			)
		else {
			Issue.record("Expected pull divergence")
			return
		}
		#expect(divergence.upstream == "origin/\(branchName)")
		#expect(divergence.aheadCount == 1)
		#expect(divergence.behindCount == 1)

		try Data("dirty".utf8).write(to: repositoryURL.appending(path: "dirty.txt"))
		do {
			try await repository.requestResolvePull(divergence, using: .rebase, at: repositoryURL)
			Issue.record("Expected dirty working tree rejection")
		} catch let error as GitRepositoryError {
			#expect(error.localizedDescription.contains("commit하거나 stash"))
		}
		try FileManager.default.removeItem(at: repositoryURL.appending(path: "dirty.txt"))
		try await repository.requestResolvePull(divergence, using: .rebase, at: repositoryURL)
		#expect(
			try requestGitOutput(
				["rev-list", "--count", "origin/\(branchName)..HEAD"], at: repositoryURL
			)
			.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
	}

	@Test
	func testForcePushWithLeaseReplacesKnownRemoteHistory() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesForcePushTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
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
		#expect(remoteHash == localHash)
	}

	@Test
	func testPushTagsPublishesLocalTagsToRemote() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesPushTagsTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
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
		#expect(remoteHash == localHash)
	}

	@Test
	func testFetchAllUpdatesRemoteTrackingReferences() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesFetchAllTests-\(UUID().uuidString).git", directoryHint: .isDirectory)
		let peerURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesFetchAllPeer-\(UUID().uuidString)", directoryHint: .isDirectory)
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
		try requestRunGit(["config", "user.name", "Groves Peer"], at: peerURL)
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

		#expect(fetchedHash == expectedHash)
	}

	@Test
	func testRequestOperationStateReportsNormalAndDetachedHead() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let repository = LocalGitRepository()

		let normalState = try await repository.requestOperationState(at: repositoryURL)
		#expect(normalState == .normal)
		try requestRunGit(["switch", "--detach"], at: repositoryURL)
		let detachedState = try await repository.requestOperationState(at: repositoryURL)
		#expect(detachedState == .detachedHead)
	}

	@Test
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
		#expect(operationState.operation?.kind == .merge)
		#expect(operationState.conflicts.count == 1)
		#expect(operationState.conflicts.first?.kind == .bothModified)
		#expect(operationState.conflicts.first?.path == "tracked.txt")
	}

	@Test
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

		#expect(historicalHash != headHash)
		#expect(tags.first(where: { $0.name == "historical-tag" })?.targetHash == historicalHash)
	}

	@Test
	func testDeleteTagRemovesLocalTag() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try requestRunGit(["tag", "release/1.0.0"], at: repositoryURL)
		let repository = LocalGitRepository()

		try await repository.requestDeleteTag(named: "release/1.0.0", at: repositoryURL)

		let tags = try await repository.requestTags(at: repositoryURL)
		#expect(!(tags.contains(where: { $0.name == "release/1.0.0" })))
	}

	@Test
	func testCreateAndDropStashIncludesUntrackedFiles() async throws {
		let repositoryURL = try makeRepository()
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		try Data("stashed".utf8).write(to: repositoryURL.appending(path: "untracked.txt"))
		let repository = LocalGitRepository()

		try await repository.requestCreateStash(message: "Sidebar work", at: repositoryURL)

		let stashes = try await repository.requestStashes(at: repositoryURL)
		let stash = try #require(stashes.first)
		#expect(stash.subject.contains("Sidebar work"))
		#expect(
			!(FileManager.default.fileExists(
				atPath: repositoryURL.appending(path: "untracked.txt").path
			)))

		try await repository.requestApplyStash(stash, at: repositoryURL)
		#expect(
			FileManager.default.fileExists(
				atPath: repositoryURL.appending(path: "untracked.txt").path
			))

		try await repository.requestDropStash(stash, at: repositoryURL)
		let remainingStashes = try await repository.requestStashes(at: repositoryURL)
		#expect(remainingStashes.isEmpty)
	}

	@Test
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
		let conflict = try #require(restoredState.conflicts.first)
		#expect(restoredState.operation?.kind == .merge)

		let repository = LocalGitRepository()
		try await repository.requestResolveConflict(conflict, using: .theirs, at: repositoryURL)
		let resolvedState = try await repository.requestOperationState(at: repositoryURL)
		#expect(resolvedState.conflicts.isEmpty)
		#expect(resolvedState.operation?.kind == .merge)
		try await repository.requestPerformOperationAction(.continue, for: .merge, at: repositoryURL)

		let completedState = try await repository.requestOperationState(at: repositoryURL)
		let contents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		#expect(completedState.isIdle)
		#expect(contents == "incoming")
	}

	@Test
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
		#expect(activeState.operation?.kind == .rebase)
		#expect(activeState.hasConflicts)
		try await repository.requestPerformOperationAction(.abort, for: .rebase, at: repositoryURL)

		let completedState = try await repository.requestOperationState(at: repositoryURL)
		#expect(completedState.isIdle)
		#expect(try currentBranch(at: repositoryURL) == "feature")
	}

	@Test
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
		let conflict = try #require(conflictedState.conflicts.first)
		try await repository.requestResolveConflict(conflict, using: .theirs, at: repositoryURL)
		try await repository.requestPerformOperationAction(.continue, for: .rebase, at: repositoryURL)

		let state = try await repository.requestOperationState(at: repositoryURL)
		let contents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		#expect(state.isIdle)
		#expect(try currentBranch(at: repositoryURL) == "feature")
		#expect(contents == "feature")
	}

	@Test
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
		#expect(state.isIdle)
		#expect(contents == "base")
	}

	@Test
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
		#expect(
			FileManager.default.fileExists(atPath: repositoryURL.appending(path: "picked.txt").path))
		let cherryPickState = try await repository.requestOperationState(at: repositoryURL)
		#expect(cherryPickState.isIdle)

		try await repository.requestRevert(commitHash: pickedHash, mainline: nil, at: repositoryURL)
		#expect(
			!(FileManager.default.fileExists(atPath: repositoryURL.appending(path: "picked.txt").path)))
		let revertState = try await repository.requestOperationState(at: repositoryURL)
		#expect(revertState.isIdle)
	}

	@Test
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
		let trackedOnly = try #require(trackedOnlyStashes.first)
		let trackedDiff = try await repository.requestStashDiff(for: trackedOnly, at: repositoryURL)
		#expect(trackedDiff.contains("tracked.txt"))
		#expect(!(trackedDiff.contains("untracked.txt")))
		#expect(FileManager.default.fileExists(atPath: untrackedURL.path))
		try await repository.requestDropStash(trackedOnly, at: repositoryURL)

		try Data("changed again".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try await repository.requestCreateStash(
			message: "Everything",
			includeUntracked: true,
			at: repositoryURL
		)
		let everythingStashes = try await repository.requestStashes(at: repositoryURL)
		let everything = try #require(everythingStashes.first)
		let everythingDiff = try await repository.requestStashDiff(for: everything, at: repositoryURL)
		#expect(everythingDiff.contains("untracked.txt"))
		#expect(!(FileManager.default.fileExists(atPath: untrackedURL.path)))
	}

	@Test
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
		let stash = try #require(stashes.first)

		try await repository.requestApplyStash(stash, at: repositoryURL)

		let state = try await repository.requestOperationState(at: repositoryURL)
		#expect(state.hasConflicts)
		#expect(state.operation == nil)
	}

	@Test
	func testRemoteBranchDeleteRemovesBranchFromRemote() async throws {
		let repositoryURL = try makeRepository()
		let remoteURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesRemoteDelete-\(UUID().uuidString).git")
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
		let remote = try #require(remotes.first)
		let branch = try #require(remote.branches.first { $0.name == "cleanup" })

		try await repository.requestDeleteRemoteBranch(branch, at: repositoryURL)

		let heads = try requestGitOutput(
			["ls-remote", "--heads", remoteURL.path, "refs/heads/cleanup"],
			at: repositoryURL
		)
		#expect(heads.isEmpty)
	}

	@Test
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
		let commit = try #require(commits.first)
		#expect(commit.author == "Author Name")
		#expect(commit.authorEmail == "author@example.com")
		#expect(commit.committer == "Committer Name")
		#expect(commit.committerEmail == "committer@example.com")
		#expect(commit.committedDate.timeIntervalSince1970 > 0)

		try Data("amended".utf8).write(to: repositoryURL.appending(path: "metadata.txt"))
		try requestRunGit(["add", "metadata.txt"], at: repositoryURL)
		try await repository.requestAmendWithoutEditingMessage(at: repositoryURL)
		commits = try await repository.requestCommitHistory(at: repositoryURL)
		let amended = try #require(commits.first)
		#expect(amended.subject == "Metadata")
		#expect(try requestGitOutput(["rev-list", "--count", "HEAD"], at: repositoryURL) == "2\n")
	}

	@Test
	func testApplyDiffHunkStagesAndDiscardsSelectedHunks() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let originalLines = (1...16).map { "line \($0)" }
		try Data((originalLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add hunk fixture"], at: repositoryURL)
		var changedLines = originalLines
		changedLines[1] = "line TWO"
		changedLines[13] = "line FOURTEEN"
		try Data((changedLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)

		let repository = LocalGitRepository()
		var changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		var change = try #require(changes.first)
		let diff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			options: GitDiffOptions(),
			at: repositoryURL
		)
		let selections = diffHunkSelections(in: diff)
		#expect(selections.count == 2)

		try await repository.requestApplyDiffHunk(
			try #require(selections.first),
			action: .stage,
			for: change,
			options: GitDiffOptions(),
			at: repositoryURL
		)
		var indexContents = try requestGitOutput(["show", ":tracked.txt"], at: repositoryURL)
		#expect(indexContents.contains("line TWO"))
		#expect(indexContents.contains("line 14"))

		changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		change = try #require(changes.first)
		let remainingDiff = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			options: GitDiffOptions(),
			at: repositoryURL
		)
		let remainingSelection = try #require(diffHunkSelections(in: remainingDiff).first)
		try await repository.requestApplyDiffHunk(
			remainingSelection,
			action: .discard,
			for: change,
			options: GitDiffOptions(),
			at: repositoryURL
		)

		let workingContents = try String(
			contentsOf: repositoryURL.appending(path: "tracked.txt"),
			encoding: .utf8
		)
		indexContents = try requestGitOutput(["show", ":tracked.txt"], at: repositoryURL)
		#expect(workingContents.contains("line TWO"))
		#expect(workingContents.contains("line 14"))
		#expect(!(workingContents.contains("line FOURTEEN")))
		#expect(workingContents == indexContents)
	}

	@Test
	func testApplyDiffHunkUnstagesOnlySelectedHunk() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let originalLines = (1...16).map { "line \($0)" }
		try Data((originalLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add unstage fixture"], at: repositoryURL)
		var changedLines = originalLines
		changedLines[1] = "line TWO"
		changedLines[13] = "line FOURTEEN"
		try Data((changedLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)

		let repository = LocalGitRepository()
		let changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let change = try #require(changes.first)
		let stagedDiff = try await repository.requestDiff(
			for: change,
			source: .staged,
			options: GitDiffOptions(),
			at: repositoryURL
		)
		let selection = try #require(diffHunkSelections(in: stagedDiff).first)
		try await repository.requestApplyDiffHunk(
			selection,
			action: .unstage,
			for: change,
			options: GitDiffOptions(),
			at: repositoryURL
		)

		let indexContents = try requestGitOutput(["show", ":tracked.txt"], at: repositoryURL)
		#expect(indexContents.contains("line 2"))
		#expect(!(indexContents.contains("line TWO")))
		#expect(indexContents.contains("line FOURTEEN"))
	}

	@Test
	func testDiffOptionsControlContextAndWhitespace() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let originalLines = (1...20).map { "line \($0)" }
		try Data((originalLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add context fixture"], at: repositoryURL)
		var changedLines = originalLines
		changedLines[9] = "line TEN"
		try Data((changedLines.joined(separator: "\n") + "\n").utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)

		let repository = LocalGitRepository()
		var changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		var change = try #require(changes.first)
		let zeroContext = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			options: GitDiffOptions(contextLineCount: 0),
			at: repositoryURL
		)
		let sixLineContext = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			options: GitDiffOptions(contextLineCount: 6),
			at: repositoryURL
		)
		#expect(
			sixLineContext.split(whereSeparator: \.isNewline).count
				> zeroContext.split(whereSeparator: \.isNewline).count)

		try Data("line    TEN\n".utf8).write(
			to: repositoryURL.appending(path: "tracked.txt")
		)
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Add whitespace fixture"], at: repositoryURL)
		try Data("line TEN\n".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		changes = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		change = try #require(changes.first)
		let ignoredWhitespace = try await repository.requestDiff(
			for: change,
			source: .unstaged,
			options: GitDiffOptions(ignoresWhitespace: true),
			at: repositoryURL
		)
		#expect(ignoredWhitespace.isEmpty)
	}

	@Test
	func testConflictContentLoadsStagesAndAcceptsBoth() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let currentBranch = try currentBranch(at: repositoryURL)
		let baseHash = try requestGitOutput(["rev-parse", "HEAD"], at: repositoryURL)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		try Data("current\n".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Current change"], at: repositoryURL)
		try requestRunGit(["switch", "--quiet", "-c", "incoming", baseHash], at: repositoryURL)
		try Data("incoming\n".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Incoming change"], at: repositoryURL)
		try requestRunGit(["switch", "--quiet", currentBranch], at: repositoryURL)
		try? requestRunGit(["merge", "incoming"], at: repositoryURL)

		let repository = LocalGitRepository()
		let state = try await repository.requestOperationState(at: repositoryURL)
		let conflict = try #require(state.conflicts.first)
		let content = try await repository.requestConflictContent(
			for: conflict,
			at: repositoryURL
		)
		#expect(content.current == "current\n")
		#expect(content.incoming == "incoming\n")
		#expect(content.hunks.count == 1)
		#expect(content.hasConflictMarkers)

		try await repository.requestResolveConflictHunk(
			try #require(content.hunks.first),
			in: conflict,
			using: .both,
			at: repositoryURL
		)
		let resolved = try await repository.requestConflictContent(
			for: conflict,
			at: repositoryURL
		)
		#expect(resolved.workingTree == "current\nincoming\n")
		#expect(!(resolved.hasConflictMarkers))
	}

	@Test
	func testConflictMarkerParserSupportsCustomSizeDiff3AndCRLF() throws {
		let contents = [
			"before",
			"<<<<<<<<<< current",
			"current",
			"|||||||||| base",
			"base",
			"==========",
			"incoming",
			">>>>>>>>>> incoming",
			"after",
		].joined(separator: "\r\n")

		let hunks = GitConflictMarkerParser.parse(contents)

		#expect(hunks.count == 1)
		#expect(hunks[0].base == "base")
		#expect(hunks[0].current == "current")
		#expect(hunks[0].incoming == "incoming")
		let resolved = try GitConflictMarkerParser.resolve(0, using: .both, in: contents)
		#expect(resolved == "before\r\ncurrent\r\nincoming\r\nafter")
	}

	@Test
	func testConflictMarkerParserRejectsMalformedAndMismatchedMarkers() {
		let malformed = [
			"<<<<<<< current",
			"current",
			"==========",
			"incoming",
			">>>>>>> incoming",
		].joined(separator: "\n")
		let short = [
			"<<<<<< current",
			"current",
			"======",
			"incoming",
			">>>>>> incoming",
		].joined(separator: "\n")

		#expect(GitConflictMarkerParser.parse(malformed).isEmpty)
		#expect(GitConflictMarkerParser.parse(short).isEmpty)
	}

	@Test
	func testConflictMarkerParserResolvesMultipleHunksInEitherOrder() throws {
		let contents = [
			"<<<<<<< current",
			"one-current",
			"=======",
			"one-incoming",
			">>>>>>> incoming",
			"middle",
			"<<<<<<< current",
			"two-current",
			"=======",
			"two-incoming",
			">>>>>>> incoming",
		].joined(separator: "\n")

		let lastFirst = try GitConflictMarkerParser.resolve(1, using: .incoming, in: contents)
		#expect(GitConflictMarkerParser.parse(lastFirst).count == 1)
		let fullyResolved = try GitConflictMarkerParser.resolve(0, using: .current, in: lastFirst)
		#expect(fullyResolved == "one-current\nmiddle\ntwo-incoming")
	}

	private func makeRepository() throws -> URL {
		let repositoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesDiscardTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: repositoryURL,
			withIntermediateDirectories: true
		)
		try requestRunGit(["init", "--quiet"], at: repositoryURL)
		try requestRunGit(["config", "user.name", "Groves Tests"], at: repositoryURL)
		try requestRunGit(["config", "user.email", "groves@example.com"], at: repositoryURL)
		try Data("original".utf8).write(to: repositoryURL.appending(path: "tracked.txt"))
		try requestRunGit(["add", "tracked.txt"], at: repositoryURL)
		try requestRunGit(["commit", "--quiet", "-m", "Initial commit"], at: repositoryURL)
		return repositoryURL
	}

	private func diffHunkSelections(in diff: String) -> [GitDiffHunkSelection] {
		diff.split(whereSeparator: \.isNewline).compactMap { line in
			guard line.hasPrefix("@@ ") else { return nil }
			let components = line.split(separator: " ")
			guard components.count >= 3,
				let oldStart = Int(components[1].dropFirst().split(separator: ",")[0]),
				let newStart = Int(components[2].dropFirst().split(separator: ",")[0])
			else { return nil }
			return GitDiffHunkSelection(oldStartLine: oldStart, newStartLine: newStart)
		}
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
