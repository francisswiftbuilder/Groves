import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitProcessRunnerTests: XCTestCase {
	func testRunnerReturnsOutputAndClassifiesCommandFailure() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner()

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"], at: repositoryURL)
		XCTAssertEqual(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "true")

		do {
			_ = try await runner.requestRun(arguments: ["not-a-command"], at: repositoryURL)
			XCTFail("Expected command failure")
		} catch GitRepositoryError.commandFailed {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	func testRunnerTimesOutNetworkOperation() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				networkPolicy: GitNetworkPolicy(operationTimeout: 0.05),
				terminationGracePeriod: 0.01
			)
		)

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.wait=!sleep 5", "wait"],
				at: repositoryURL,
				isNetworkOperation: true
			)
			XCTFail("Expected timeout")
		} catch GitRepositoryError.timeout {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	func testRunnerCancellationTerminatesCommand() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(terminationGracePeriod: 0.01)
		)
		let task = Task {
			try await runner.requestRun(
				arguments: ["-c", "alias.wait=!sleep 5", "wait"],
				at: repositoryURL
			)
		}

		try await Task.sleep(for: .milliseconds(50))
		task.cancel()

		do {
			_ = try await task.value
			XCTFail("Expected cancellation")
		} catch is CancellationError {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	private func makeRepository() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "TreesProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git", "-C", url.path, "init", "--quiet"]
		try process.run()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { throw GitRepositoryError.invalidRepository }
		return url
	}
}
