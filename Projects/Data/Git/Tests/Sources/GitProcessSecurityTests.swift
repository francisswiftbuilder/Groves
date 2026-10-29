import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitProcessSecurityTests {
	@Test
	func testPreCancelledTaskDoesNotStartProcess() async throws {
		let repositoryURL = try makeTemporaryRepository()
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
			Issue.record("Expected cancellation")
		} catch is CancellationError {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
		#expect(
			!(FileManager.default.fileExists(atPath: markerURL.path)),
			"A cancelled task must not start the git process")
	}

	@Test
	func testLowSpeedFailureIsClassifiedAsTimeout() async throws {
		let repositoryURL = try makeTemporaryRepository()
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
			Issue.record("Expected timeout")
		} catch GitRepositoryError.timeout {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test
	func testLargeStandardOutputIsCollectedWithoutDeadlock() async throws {
		let repositoryURL = try makeTemporaryRepository()
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

		#expect(result.standardOutput.utf8.count > 5_000_000)
		#expect(result.standardOutput.contains("line 199999 of a very large staged file"))
	}

	@Test
	func testUnusableKnownHostsFileStopsTheNetworkOperation() async throws {
		let repositoryURL = try makeTemporaryRepository()
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
			Issue.record("Expected hostVerification")
		} catch GitRepositoryError.hostVerification {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		#expect(
			!(FileManager.default.fileExists(atPath: markerURL.path)),
			"An unusable trust scope must not fall back to the user's known_hosts")
	}

	@Test
	func testHTTPSNetworkOperationRunsWithoutAnSSHTrustScope() async throws {
		let repositoryURL = try makeTemporaryRepository()
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

		#expect(result.standardOutput.contains("true"))
	}

	@Test
	func testLocalOperationsRunWithoutATrustScope() async throws {
		let repositoryURL = try makeTemporaryRepository()
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

		#expect(result.standardOutput.contains("true"))
	}

	@Test
	func testEmbeddedCredentialRemoteURLIsRejected() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let repository = LocalGitRepository()

		do {
			_ = try await repository.requestCloneRepository(
				from: "https://user:token@127.0.0.1:1/secret.git",
				into: directoryURL
			)
			Issue.record("Expected the embedded credential URL to be rejected")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
		#expect(
			!(FileManager.default.fileExists(
				atPath: directoryURL.appending(path: "secret").path
			)))
	}
}
