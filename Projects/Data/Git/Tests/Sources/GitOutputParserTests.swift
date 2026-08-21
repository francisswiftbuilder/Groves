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

	func testDiscardRestoresTrackedFileAndIndex() async throws {
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
		XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
		XCTAssertTrue(remainingChanges.isEmpty)
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
		let diff = try await repository.requestDiff(for: change, at: repositoryURL)

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
		let diff = try await repository.requestDiff(for: change, at: repositoryURL)

		XCTAssertTrue(diff.contains("new file mode"))
		XCTAssertTrue(diff.contains("index 0000000..e69de29"))
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

	func testDiscardDeletesStagedAddedFile() async throws {
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
		XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
		XCTAssertTrue(remainingChanges.isEmpty)
	}

	func testDiscardRestoresStagedRename() async throws {
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
		XCTAssertEqual(try String(contentsOf: originalFileURL, encoding: .utf8), "original")
		XCTAssertFalse(FileManager.default.fileExists(atPath: renamedFileURL.path))
		XCTAssertTrue(remainingChanges.isEmpty)
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
