import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitImageDiffLoadingTests {
	@Test
	func testRequestImageDiffRejectsOversizedWorkingTreeAndIndexData() async throws {
		let repositoryURL = try makeTemporaryRepository(
			name: "GrovesImageDiffLoadingTests"
		)
		defer {
			try? FileManager.default.removeItem(at: repositoryURL)
		}
		let fileURL = repositoryURL.appending(path: "oversized.png")
		try Data(repeating: 0, count: 10 * 1_024 * 1_024 + 1).write(to: fileURL)
		let repository = LocalGitRepository()

		let unstagedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let unstagedChange = try #require(unstagedChanges.first)
		do {
			_ = try await repository.requestImageDiff(
				for: unstagedChange,
				source: .unstaged,
				at: repositoryURL
			)
			Issue.record("Expected the working tree image to exceed the preview limit")
		} catch GitRepositoryError.fileTooLarge {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		try runGit(arguments: ["add", "oversized.png"], at: repositoryURL)
		let stagedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let stagedChange = try #require(stagedChanges.first)
		do {
			_ = try await repository.requestImageDiff(
				for: stagedChange,
				source: .staged,
				at: repositoryURL
			)
			Issue.record("Expected the index image to exceed the preview limit")
		} catch GitRepositoryError.fileTooLarge {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	private func runGit(arguments: [String], at repositoryURL: URL) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", repositoryURL.path] + arguments
		try process.run()
		process.waitUntilExit()
		#expect(process.terminationStatus == 0)
	}
}
