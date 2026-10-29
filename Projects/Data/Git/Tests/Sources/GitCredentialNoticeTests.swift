import CoreGitCredential
import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct GitCredentialNoticeTests {
	@Test
	func testLocalCommandsDoNotAccessCredentialPersistence() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let error = GitCredentialStoreError(operation: .copySecret, status: -25308)
		let store = GitCredentialPersistingStub(commitError: error, discardError: error)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(noticeHandler: { recorder.record($0) }),
			credentialStore: store
		)

		_ = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"], at: repositoryURL)

		#expect(store.commitCount == 0)
		#expect(store.discardCount == 0)
		#expect(recorder.notices.isEmpty)
	}

	@Test
	func testCredentialPersistenceFailureKeepsTheCommandResult() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let commitError = GitCredentialStoreError(
			operation: .copySecret,
			status: -25308
		)
		let store = GitCredentialPersistingStub(commitError: commitError)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		let result = try await runner.requestRun(
			arguments: ["rev-parse", "--is-inside-work-tree"],
			at: repositoryURL,
			isNetworkOperation: true
		)

		#expect(result.standardOutput.contains("true"))
		#expect(
			recorder.notices == [
				.credentialPersistenceFailed(
					diagnostic: "commit: \(commitError.diagnosticDescription)"
				)
			])
		#expect(store.discardCount == 1, "The pending credential must be discarded")
	}

	@Test
	func testSuccessfulCredentialPersistenceSendsNoNotice() async throws {
		let repositoryURL = try makeTemporaryRepository()
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
			at: repositoryURL,
			isNetworkOperation: true
		)

		#expect(recorder.notices.isEmpty)
		#expect(store.commitCount == 1)
	}

	@Test
	func testUnrecoverableDiscardPreservesBothDiagnosticsInASingleNotice() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let commitError = GitCredentialStoreError(operation: .copySecret, status: -25308)
		let discardError = GitCredentialStoreError(operation: .delete, status: -25300)
		let store = GitCredentialPersistingStub(
			commitError: commitError,
			discardError: discardError
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
			at: repositoryURL,
			isNetworkOperation: true
		)

		#expect(
			recorder.notices == [
				.credentialPersistenceFailed(
					diagnostic: "commit: \(commitError.diagnosticDescription); "
						+ "discard: \(discardError.diagnosticDescription)"
				)
			])
	}

	@Test
	func testFailedCommandSendsNoCredentialNotice() async throws {
		let repositoryURL = try makeTemporaryRepository()
		defer { try? FileManager.default.removeItem(at: repositoryURL) }
		let store = GitCredentialPersistingStub(
			commitError: GitCredentialStoreError(operation: .copySecret, status: -25308)
		)
		let recorder = GitProcessNoticeRecorder()
		let runner = GitProcessRunner(
			configuration: GitProcessConfiguration(
				noticeHandler: { [recorder] notice in recorder.record(notice) }
			),
			credentialStore: store
		)

		do {
			_ = try await runner.requestRun(
				arguments: ["not-a-command"], at: repositoryURL, isNetworkOperation: true)
			Issue.record("Expected command failure")
		} catch GitRepositoryError.commandFailed {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}

		#expect(store.commitCount == 0, "A failed command must not commit credentials")
		#expect(recorder.notices.isEmpty)
	}

	@Test
	func testCredentialPersistenceFailureKeepsTheClonedRepository() async throws {
		let directoryURL = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directoryURL) }
		let sourceURL = try makeTemporaryRepository(name: "GrovesNoticeSource")
		defer { try? FileManager.default.removeItem(at: sourceURL) }
		let recorder = GitProcessNoticeRecorder()
		let commitError = GitCredentialStoreError(operation: .copySecret, status: -25308)
		let repository = LocalGitRepository(
			runner: GitProcessRunner(
				configuration: GitProcessConfiguration(
					noticeHandler: { [recorder] notice in recorder.record(notice) }
				),
				credentialStore: GitCredentialPersistingStub(commitError: commitError)
			)
		)

		let clonedURL = try await repository.requestCloneRepository(
			from: sourceURL.path,
			into: directoryURL
		)

		#expect(
			FileManager.default.fileExists(atPath: clonedURL.appending(path: ".git").path),
			"A credential persistence failure must not delete the cloned repository")
		#expect(
			recorder.notices == [
				.credentialPersistenceFailed(
					diagnostic: "commit: \(commitError.diagnosticDescription)"
				)
			])
	}
}
