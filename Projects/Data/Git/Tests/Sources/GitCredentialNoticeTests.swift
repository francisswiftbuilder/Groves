import CoreGitCredential
import DomainGitInterface
import Foundation
import XCTest

@testable import DataGit

final class GitCredentialNoticeTests: XCTestCase {
	func testCredentialPersistenceFailureKeepsTheCommandResult() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let store = GitCredentialPersistingStub(
			commitError: GitCredentialStoreError.keychain(-25308)
		)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL
		)

		XCTAssertTrue(result.standardOutput.contains("true"))
		XCTAssertEqual(recorder.notices, [.credentialPersistenceFailed])
		XCTAssertEqual(store.discardCount, 1, "The pending credential must be discarded")
	}

	func testSuccessfulCredentialPersistenceSendsNoNotice() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let store = GitCredentialPersistingStub()
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		_ = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL
		)

		XCTAssertTrue(recorder.notices.isEmpty)
		XCTAssertEqual(store.commitCount, 1)
	}

	func testUnrecoverableDiscardStillSendsASingleNotice() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let store = GitCredentialPersistingStub(
			commitError: GitCredentialStoreError.keychain(-25308),
			discardError: GitCredentialStoreError.keychain(-25300)
		)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		_ = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL
		)

		XCTAssertEqual(recorder.notices, [.credentialPersistenceFailed])
	}

	func testFailedCommandSendsNoCredentialNotice() async throws {
		let repositoryURL = try GitTestRepositoryFactory.makeRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let store = GitCredentialPersistingStub(
			commitError: GitCredentialStoreError.keychain(-25308)
		)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		do {
			_ = try await runner.requestRun(arguments: ["not-a-command"], at: repositoryURL)
			XCTFail("Expected command failure")
		} catch GitRepositoryError.commandFailed {
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		XCTAssertEqual(store.commitCount, 0, "A failed command must not commit credentials")
		XCTAssertTrue(recorder.notices.isEmpty)
	}

	func testCredentialPersistenceFailureKeepsTheClonedRepository() async throws {
		let directoryURL = try GitTestRepositoryFactory.makeDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let sourceURL = try GitTestRepositoryFactory.makeRepository(name: "TreesNoticeSource")
		defer { try? FileManager.default.removeItem(at: sourceURL) }
		let recorder = GitProcessNoticeRecorder()
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					noticeHandler: { [recorder] notice in recorder.record(notice) }
				),
				credentialStore: GitCredentialPersistingStub(
					commitError: GitCredentialStoreError.keychain(-25308)
				)
			)
		)

		let clonedURL = try await repository.requestCloneRepository(
			from: sourceURL.path,
			into: directoryURL
		)

		XCTAssertTrue(
			FileManager.default.fileExists(atPath: clonedURL.appending(path: ".git").path),
			"A credential persistence failure must not delete the cloned repository"
		)
		XCTAssertEqual(recorder.notices, [.credentialPersistenceFailed])
	}
}
