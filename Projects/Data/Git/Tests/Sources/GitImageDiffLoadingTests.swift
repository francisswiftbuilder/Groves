import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitImageDiffLoadingTests: XCTestCase {
	func testRequestImageDiffRejectsOversizedWorkingTreeAndIndexData() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository(
			name: "TreesImageDiffLoadingTests"
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "oversized.png")
		try Data(repeating: 0, count: 10 * 1_024 * 1_024 + 1).write(to: fileURL)
		let repository = LocalGitRepository()

		let unstagedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let unstagedChange = try XCTUnwrap(unstagedChanges.first)
		do {
			_ = try await repository.requestImageDiff(
				for: unstagedChange,
				source: .unstaged,
				at: repositoryURL
			)
			XCTFail("Expected the working tree image to exceed the preview limit")
		} catch GitRepositoryError.fileTooLarge {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		try runGit(arguments: ["add", "oversized.png"], at: repositoryURL)
		let stagedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let stagedChange = try XCTUnwrap(stagedChanges.first)
		do {
			_ = try await repository.requestImageDiff(
				for: stagedChange,
				source: .staged,
				at: repositoryURL
			)
			XCTFail("Expected the index image to exceed the preview limit")
		} catch GitRepositoryError.fileTooLarge {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	private func runGit(arguments: [String], at repositoryURL: URL) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", repositoryURL.path] + arguments
		try process.run()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationStatus, 0)
	}
}
