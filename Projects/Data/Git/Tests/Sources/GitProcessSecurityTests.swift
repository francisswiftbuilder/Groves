import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitProcessSecurityTests: XCTestCase {
	func testPreCancelledTaskDoesNotStartProcess() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let markerURL = repositoryURL.appending(path: "started.marker")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(terminationGracePeriod: 0.01)
		)
		let gate = GitTestGate()
		let task = Task {
			await gate.wait()
			return try await runner.requestRun(
				arguments: ["-c", "alias.mark=!touch '\(markerURL.path)'", "mark"],
				at: repositoryURL
			)
		}

		task.cancel()
		await gate.open()

		do {
			_ = try await task.value
			XCTFail("Expected cancellation")
		} catch is CancellationError {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: markerURL.path),
			"A cancelled task must not start the git process"
		)
	}

	func testLowSpeedFailureIsClassifiedAsTimeout() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner()
		let message =
			"fatal: unable to access: Operation too slow. "
			+ "Less than 1 bytes/sec transferred the last 30 seconds"

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.slow=!echo \"\(message)\" >&2; exit 128", "slow"],
				at: repositoryURL,
				isNetworkOperation: true
			)
			XCTFail("Expected timeout")
		} catch GitRepositoryError.timeout {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	func testLargeStandardOutputIsCollectedWithoutDeadlock() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let lines = (0..<200_000).map { "line \($0) of a very large staged file" }
		try lines.joined(separator: "\n").write(
			to: repositoryURL.appending(path: "large.txt"),
			atomically: true,
			encoding: .utf8
		)
		let runner = GitProcessRunner()
		_ = try await runner.requestRun(arguments: ["add", "large.txt"], at: repositoryURL)

		let result = try await runner.requestRun(
			arguments: ["diff", "--cached"],
			at: repositoryURL
		)

		XCTAssertGreaterThan(result.standardOutput.utf8.count, 5_000_000)
		XCTAssertTrue(result.standardOutput.contains("line 199999 of a very large staged file"))
	}

	func testUnusableKnownHostsFileStopsTheNetworkOperation() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let unusableKnownHostsURL = repositoryURL.appending(
			path: "known_hosts",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: unusableKnownHostsURL,
			withIntermediateDirectories: true
		)
		let markerURL = repositoryURL.appending(path: "started.marker")
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(userKnownHostsURL: unusableKnownHostsURL)
		)

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.mark=!touch '\(markerURL.path)'", "mark"],
				at: repositoryURL,
				isNetworkOperation: true,
				requiresSSHTrustScope: true
			)
			XCTFail("Expected hostVerification")
		} catch GitRepositoryError.hostVerification {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		XCTAssertFalse(
			FileManager.default.fileExists(atPath: markerURL.path),
			"An unusable trust scope must not fall back to the user's known_hosts"
		)
	}

	func testHTTPSNetworkOperationRunsWithoutAnSSHTrustScope() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let unusableKnownHostsURL = repositoryURL.appending(
			path: "known_hosts",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: unusableKnownHostsURL,
			withIntermediateDirectories: true
		)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(userKnownHostsURL: unusableKnownHostsURL)
		)

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL,
			isNetworkOperation: true
		)

		XCTAssertTrue(result.standardOutput.contains("true"))
	}

	func testLocalOperationsRunWithoutATrustScope() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let unusableKnownHostsURL = repositoryURL.appending(
			path: "known_hosts",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: unusableKnownHostsURL,
			withIntermediateDirectories: true
		)
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(userKnownHostsURL: unusableKnownHostsURL)
		)

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL
		)

		XCTAssertTrue(result.standardOutput.contains("true"))
	}

	func testEmbeddedCredentialRemoteURLIsRejected() async throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let repository = LocalGitRepository()

		do {
			_ = try await repository.requestCloneRepository(
				from: "https://user:token@127.0.0.1:1/secret.git",
				into: directoryURL
			)
			XCTFail("Expected the embedded credential URL to be rejected")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
		XCTAssertFalse(
			FileManager.default.fileExists(
				atPath: directoryURL.appending(path: "secret").path
			)
		)
	}
}
