import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitOutputParserTests: XCTestCase {
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

	func testBuildFileTreeGroupsFilesByDirectory() {
		let nodes = GitOutputParser.buildFileTree(
			paths: ["Sources/App.swift", "Sources/Feature/View.swift", "README.md"]
		)

		XCTAssertEqual(nodes.map(\.name), ["Sources", "README.md"])
		XCTAssertEqual(nodes.first?.children.map(\.name), ["Feature", "App.swift"])
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
