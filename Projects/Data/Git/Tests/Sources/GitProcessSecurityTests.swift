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
	@Test
	func repositoryReadsPreserveIndexAndExistingLock() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		let file = url.appending(path: "file.txt")
		try Data("content\n".utf8).write(to: file)
		_ = try await runner.requestRun(arguments: ["add", "--", "file.txt"], at: url)
		_ = try await runner.requestRun(
			arguments: ["config", "diff.autoRefreshIndex", "true"], at: url)
		let index = url.appending(path: ".git/index")
		let original = try Data(contentsOf: index)
		try FileManager.default.setAttributes(
			[.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: file.path)
		let change = WorkingTreeChange(
			path: "file.txt", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)

		for hasExistingLock in [false, true] {
			let lock = index.appendingPathExtension("lock")
			let contents = Data("external lock".utf8)
			if hasExistingLock { try contents.write(to: lock) }
			_ = try await repository.requestWorkingTreeChanges(at: url)
			_ = try await repository.requestOperationState(at: url)
			let diff = try await repository.requestDiff(
				for: change, source: .unstaged, options: GitDiffOptions(), at: url)
			#expect(diff.isEmpty)
			#expect(try Data(contentsOf: index) == original)
			if hasExistingLock {
				#expect(try Data(contentsOf: lock) == contents)
			} else {
				#expect(!FileManager.default.fileExists(atPath: lock.path))
			}
		}
	}

	@Test(arguments: ["file[1].txt", "file*.txt", ":(glob)*.txt"])
	func fileOperationsTreatSelectedPathsLiterally(path: String) async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		let selected = url.appending(path: path)
		let unrelated = url.appending(path: "file1.txt")
		for file in [selected, unrelated] { try Data("base\n".utf8).write(to: file) }
		_ = try await runner.requestRun(arguments: ["add", "."], at: url)
		_ = try await runner.requestRun(
			arguments: [
				"-c", "user.name=Review", "-c", "user.email=review@example.com", "commit", "-m", "base",
			], at: url)
		for file in [selected, unrelated] { try Data("changed\n".utf8).write(to: file) }

		try await repository.requestStage(path: path, at: url)
		let staged = try await repository.requestWorkingTreeChanges(at: url).filter(\.isStaged)
		#expect(staged.map(\.path) == [path])
		try await repository.requestUnstage(path: path, at: url)
		let change = WorkingTreeChange(
			path: path, previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		try await repository.requestDiscard(change: change, at: url)
		#expect(try String(contentsOf: selected, encoding: .utf8) == "base\n")
		#expect(try String(contentsOf: unrelated, encoding: .utf8) == "changed\n")
	}

	@Test
	func diffPreviewDoesNotRunExternalToolsOrCreateTextConversionCache() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		let file = url.appending(path: "file.txt")
		try Data("base\n".utf8).write(to: file)
		try Data("file.txt diff=review\n".utf8).write(to: url.appending(path: ".gitattributes"))
		_ = try await runner.requestRun(arguments: ["add", "."], at: url)
		let tool = url.appending(path: ".git/diff-tool")
		let marker = url.appending(path: ".git/external-tool-started")
		let escapedMarker = marker.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		touch '\(escapedMarker)'
		printf 'converted\\n'
		""".write(to: tool, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
		for key in ["diff.review.command", "diff.review.textconv"] {
			_ = try await runner.requestRun(arguments: ["config", key, tool.path], at: url)
		}
		_ = try await runner.requestRun(
			arguments: ["config", "diff.review.cachetextconv", "true"], at: url)
		try Data("changed\n".utf8).write(to: file)
		let change = WorkingTreeChange(
			path: "file.txt", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)

		let diff = try await repository.requestDiff(
			for: change, source: .unstaged, options: GitDiffOptions(), at: url)

		#expect(diff.contains("-base"))
		#expect(diff.contains("+changed"))
		#expect(!FileManager.default.fileExists(atPath: marker.path))
		let refs = try await runner.requestRun(
			arguments: ["for-each-ref", "refs/notes/textconv"], at: url)
		#expect(refs.standardOutput.isEmpty)
	}

	@Test
	func initialCommitAmendPreviewDoesNotWriteAnEmptyTreeObject() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		try Data("base\n".utf8).write(to: url.appending(path: "file.txt"))
		_ = try await runner.requestRun(arguments: ["add", "."], at: url)
		_ = try await runner.requestRun(
			arguments: [
				"-c", "user.name=Review", "-c", "user.email=review@example.com", "commit", "-m", "base",
			], at: url)
		let hash = try await runner.requestRun(
			arguments: ["hash-object", "-t", "tree", "--stdin"], at: url, standardInput: "")
		let objectID = hash.standardOutput.trimmingCharacters(in: .newlines)
		let objectURL = url.appending(
			path: ".git/objects/\(objectID.prefix(2))/\(objectID.dropFirst(2))")
		#expect(!FileManager.default.fileExists(atPath: objectURL.path))

		let changes = try await repository.requestAmendChanges(at: url)

		#expect(changes.map(\.path) == ["file.txt"])
		#expect(!FileManager.default.fileExists(atPath: objectURL.path))
	}

	@Test
	func commitDoesNotStartAutomaticObjectPacking() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		for (key, value) in [
			("user.name", "Review"), ("user.email", "review@example.com"),
			("maintenance.auto", "true"), ("maintenance.autoDetach", "false"),
			("maintenance.loose-objects.enabled", "true"), ("maintenance.loose-objects.auto", "1"),
		] {
			_ = try await runner.requestRun(arguments: ["config", key, value], at: url)
		}
		try Data("content\n".utf8).write(to: url.appending(path: "file.txt"))
		try await repository.requestStage(path: "file.txt", at: url)

		try await repository.requestCommit(subject: "base", body: "", amend: false, at: url)

		let packs = try FileManager.default.contentsOfDirectory(
			atPath: url.appending(path: ".git/objects/pack").path)
		#expect(packs.isEmpty)
		#expect(try await repository.requestCommitHistory(at: url).count == 1)
	}

	@Test
	func historyAndStashReadsDoNotLaunchSignatureVerification() async throws {
		let url = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: url) }
		let runner = GitProcessRunner()
		let repository = LocalGitRepository(runner: runner)
		try Data("base\n".utf8).write(to: url.appending(path: "file.txt"))
		_ = try await runner.requestRun(arguments: ["add", "."], at: url)
		let tree = try await runner.requestRun(arguments: ["write-tree"], at: url)
		let contents = """
			tree \(tree.standardOutput.trimmingCharacters(in: .newlines))
			author Review <review@example.com> 1 +0000
			committer Review <review@example.com> 1 +0000
			gpgsig -----BEGIN PGP SIGNATURE-----
			 fake
			 -----END PGP SIGNATURE-----

			base

			"""
		let object = try await runner.requestRun(
			arguments: ["hash-object", "-t", "commit", "-w", "--stdin"], at: url, standardInput: contents)
		let hash = object.standardOutput.trimmingCharacters(in: .newlines)
		_ = try await runner.requestRun(arguments: ["update-ref", "HEAD", hash], at: url)
		_ = try await runner.requestRun(
			arguments: ["update-ref", "--create-reflog", "-m", "WIP on main: base", "refs/stash", hash],
			at: url)
		let tool = url.appending(path: ".git/gpg-tool")
		let marker = url.appending(path: ".git/gpg-started")
		let escapedMarker = marker.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		touch '\(escapedMarker)'
		exit 1
		""".write(to: tool, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
		for (key, value) in [("gpg.program", tool.path), ("log.showSignature", "true")] {
			_ = try await runner.requestRun(arguments: ["config", key, value], at: url)
		}

		let commits = try await repository.requestCommitHistory(at: url)
		let commit = try #require(commits.first)
		let diff = try await repository.requestCommitDiff(
			for: commit, options: GitDiffOptions(), at: url)
		let stashes = try await repository.requestStashes(at: url)

		#expect(commits.count == 1)
		#expect(diff.contains("+base"))
		#expect(stashes.count == 1)
		#expect(!FileManager.default.fileExists(atPath: marker.path))
	}

}
