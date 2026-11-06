import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitCloneCleanupTests {
	@Test
	func testCancelledCloneLeavesNoDestinationBehind() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let sourceURL = try makeTemporaryRepository(name: "GrovesCloneSource")
		defer { try? FileManager.default.removeItem(at: sourceURL) }
		let repository = LocalGitRepository(
			configuration: GitProcessConfiguration(terminationGracePeriod: 0.01)
		)
		let task = Task {
			try await repository.requestCloneRepository(
				from: sourceURL.path,
				into: directoryURL
			)
		}

		task.cancel()

		do {
			_ = try await task.value
		} catch {}

		let destinationURL = directoryURL.appending(path: sourceURL.lastPathComponent)
		#expect(
			!(FileManager.default.fileExists(atPath: destinationURL.path)),
			"A cancelled clone must be retryable at the same location")
	}

	@Test
	func testExistingDestinationIsReportedWithoutBeingRemoved() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let destinationURL = directoryURL.appending(path: "Existing", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
		let existingFileURL = destinationURL.appending(path: "keep.txt")
		try Data("keep".utf8).write(to: existingFileURL)
		let repository = LocalGitRepository()

		do {
			_ = try await repository.requestCloneRepository(
				from: "https://127.0.0.1:1/Existing.git",
				into: directoryURL
			)
			Issue.record("Expected repositoryAlreadyExists")
		} catch GitRepositoryError.repositoryAlreadyExists {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		#expect(
			FileManager.default.fileExists(atPath: existingFileURL.path),
			"An existing directory must never be removed by a failed clone")
	}

	@Test
	func successfulCloneMovesIntoTheFinalDestination() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let source = try makeTemporaryRepository(name: "GrovesCloneSource")
		defer { try? FileManager.default.removeItem(at: source) }
		let repository = LocalGitRepository()

		let cloned = try await repository.requestCloneRepository(from: source.path, into: directory)

		#expect(cloned == directory.appending(path: source.lastPathComponent).standardizedFileURL)
		#expect(
			try await repository.requestRepositoryRoot(at: cloned) == cloned.resolvingSymlinksInPath())
	}

	@Test
	func failedCloneRemovesItsTemporaryDestination() async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let repository = LocalGitRepository()

		await #expect(throws: GitRepositoryError.self) {
			try await repository.requestCloneRepository(
				from: directory.appending(path: "missing.git").path, into: directory)
		}

		#expect(!FileManager.default.fileExists(atPath: directory.appending(path: "missing").path))
		let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
		#expect(!files.contains { $0.hasPrefix(".groves-clone-") })
	}

	@Test(arguments: [false, true])
	func clonePreservesAReplacementDestination(reportsSuccess: Bool) async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let destination = directory.appending(path: "project")
		let replacement = directory.appending(path: "replacement")
		try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)
		try Data("external work".utf8).write(to: replacement.appending(path: "keep.txt"))
		let executable = directory.appending(path: "test-git")
		let escapedDestination = destination.path.replacingOccurrences(of: "'", with: "'\\''")
		let escapedReplacement = replacement.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		case " $* " in
		  *" clone "*)
		    if [ -d '\(escapedDestination)' ]; then rmdir '\(escapedDestination)'; fi
		    mv '\(escapedReplacement)' '\(escapedDestination)'
		    exit \(reportsSuccess ? 0 : 1)
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			configuration: GitProcessConfiguration(executableURL: executable))

		await #expect(throws: GitRepositoryError.self) {
			try await repository.requestCloneRepository(
				from: "https://example.com/project.git", into: directory)
		}

		#expect(
			try String(contentsOf: destination.appending(path: "keep.txt"), encoding: .utf8)
				== "external work")
	}

	@Test(arguments: [false, true])
	func clonePreservesFilesAddedAtTheDestination(reportsSuccess: Bool) async throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }
		let destination = directory.appending(path: "project")
		let executable = directory.appending(path: "test-git")
		let escapedDestination = destination.path.replacingOccurrences(of: "'", with: "'\\''")
		try """
		#!/bin/sh
		case " $* " in
		  *" clone "*)
		    mkdir -p '\(escapedDestination)'
		    printf 'external work' > '\(escapedDestination)/keep.txt'
		    exit \(reportsSuccess ? 0 : 1)
		    ;;
		esac
		exec /usr/bin/git "$@"
		""".write(to: executable, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
		let repository = LocalGitRepository(
			configuration: GitProcessConfiguration(executableURL: executable))

		await #expect(throws: GitRepositoryError.self) {
			try await repository.requestCloneRepository(
				from: "https://example.com/project.git", into: directory)
		}

		#expect(
			try String(contentsOf: destination.appending(path: "keep.txt"), encoding: .utf8)
				== "external work")
		let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
		#expect(!files.contains { $0.hasPrefix(".groves-clone-") })
	}

	@Test
	func testChangedHostKeyIsClassifiedAsHostVerification() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner()
		let message = "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.changed=!echo \"\(message)\" >&2; exit 128", "changed"],
				at: repositoryURL,
				isNetworkOperation: true
			)
			Issue.record("Expected hostVerification")
		} catch GitRepositoryError.hostVerification {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test
	func testEmbeddedCredentialRemoteURLIsRejectedWhenConfiguringRemotes() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let repository = LocalGitRepository()

		do {
			try await repository.requestAddRemote(
				named: "origin",
				fetchURL: "https://groves:token@github.com/owner/repo.git",
				pushURL: nil,
				at: repositoryURL
			)
			Issue.record("Expected invalidRemoteURL")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		let remotes = try await repository.requestRemotes(at: repositoryURL)
		#expect(remotes.isEmpty)
	}

	@Test
	func testEmbeddedCredentialRemoteURLIsRejectedWhenUpdatingRemotes() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let repository = LocalGitRepository()
		try await repository.requestAddRemote(
			named: "origin",
			fetchURL: "ssh://git@github.com/owner/repo.git",
			pushURL: nil,
			at: repositoryURL
		)

		do {
			try await repository.requestUpdateRemote(
				named: "origin",
				fetchURL: "https://groves@github.com/owner/repo.git",
				pushURL: nil,
				at: repositoryURL
			)
			Issue.record("Expected invalidRemoteURL")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		let remotes = try await repository.requestRemotes(at: repositoryURL)
		#expect(remotes.first?.fetchURL == "ssh://git@github.com/owner/repo.git")
	}
}
