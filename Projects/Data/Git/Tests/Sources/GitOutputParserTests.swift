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
}
