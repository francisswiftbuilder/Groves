import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitCloneCleanupTests: XCTestCase {
	func testCancelledCloneLeavesNoDestinationBehind() async throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let sourceURL = try GitTestRepositoryFactory.makeRepository(name: "TreesCloneSource")
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
		XCTAssertFalse(
			FileManager.default.fileExists(atPath: destinationURL.path),
			"A cancelled clone must be retryable at the same location"
		)
	}

	func testExistingDestinationIsReportedWithoutBeingRemoved() async throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
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
			XCTFail("Expected repositoryAlreadyExists")
		} catch GitRepositoryError.repositoryAlreadyExists {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: existingFileURL.path),
			"An existing directory must never be removed by a failed clone"
		)
	}

	func testChangedHostKeyIsClassifiedAsHostVerification() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let runner = GitProcessRunner()
		let message = "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!"

		do {
			_ = try await runner.requestRun(
				arguments: ["-c", "alias.changed=!echo \"\(message)\" >&2; exit 128", "changed"],
				at: repositoryURL,
				isNetworkOperation: true
			)
			XCTFail("Expected hostVerification")
		} catch GitRepositoryError.hostVerification {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}
	}

	func testEmbeddedCredentialRemoteURLIsRejectedWhenConfiguringRemotes() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let repository = LocalGitRepository()

		do {
			try await repository.requestAddRemote(
				named: "origin",
				fetchURL: "https://trees:token@github.com/owner/repo.git",
				pushURL: nil,
				at: repositoryURL
			)
			XCTFail("Expected invalidRemoteURL")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		let remotes = try await repository.requestRemotes(at: repositoryURL)
		XCTAssertTrue(remotes.isEmpty)
	}

	func testEmbeddedCredentialRemoteURLIsRejectedWhenUpdatingRemotes() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
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
				fetchURL: "https://trees@github.com/owner/repo.git",
				pushURL: nil,
				at: repositoryURL
			)
			XCTFail("Expected invalidRemoteURL")
		} catch GitRepositoryError.invalidRemoteURL {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		let remotes = try await repository.requestRemotes(at: repositoryURL)
		XCTAssertEqual(remotes.first?.fetchURL, "ssh://git@github.com/owner/repo.git")
	}
}
