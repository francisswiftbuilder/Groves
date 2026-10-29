import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitProcessRunnerTests {
	@Test
	func testCancelledSuccessfulExitDoesNotCommitCredentials() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let executableURL = directoryURL.appending(path: "test-git")
		let markerURL = directoryURL.appending(path: "started")
		let escapedMarkerPath = markerURL.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		trap 'exit 0' TERM
		touch '\(escapedMarkerPath)'
		while :; do sleep 0.01; done
		""".write(to: executableURL, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
		let store = GitCredentialPersistingStub()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(executableURL: executableURL),
			credentialStore: store
		)
		let task = Task {
			try await runner.requestRun(arguments: [], at: directoryURL, isNetworkOperation: true)
		}
		defer { task.cancel() }
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while !FileManager.default.fileExists(atPath: markerURL.path), clock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(FileManager.default.fileExists(atPath: markerURL.path))

		task.cancel()
		do {
			_ = try await task.value
			Issue.record("A cancelled operation must not succeed even when the process exits with zero")
		} catch is CancellationError {}

		#expect(store.commitCount == 0)
		#expect(store.discardCount == 1)
	}

	@Test
	func testRunnerReturnsOutputAndClassifiesCommandFailure() async throws {
		let repositoryURL = try makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner()

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"], at: repositoryURL)
		#expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true")

		do {
			_ = try await runner.requestRun(arguments: ["not-a-command"], at: repositoryURL)
			Issue.record("Expected command failure")
		} catch GitRepositoryError.commandFailed {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test
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
			Issue.record("Expected timeout")
		} catch GitRepositoryError.timeout {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test
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
			Issue.record("Expected cancellation")
		} catch is CancellationError {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	private func makeRepository() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appending(path: "GrovesProcessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
