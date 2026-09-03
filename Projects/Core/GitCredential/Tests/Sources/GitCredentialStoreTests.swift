import Foundation
import Security
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialStoreTests {
	@Test
	func pendingCredentialCommitsOnlyAfterSuccess() throws {
		let service = "Groves.Tests.\(UUID().uuidString)"
		let store = makeTestCredentialStore(service: service)
		let descriptor = GitCredentialDescriptor(kind: .ssh, host: "SSH Key", account: "id_ed25519")

		do {
			try store.savePending(secret: "pending-secret", for: descriptor, operationID: "success")
		} catch {
			Issue.record("savePending failed: \(error)")
			return
		}
		do {
			#expect(try store.secret(for: descriptor) == nil)
		} catch {
			Issue.record("secret before commit failed: \(error)")
			return
		}
		do {
			try store.commitPending(operationID: "success")
		} catch {
			Issue.record("commitPending failed: \(error)")
			return
		}
		do {
			#expect(try store.secret(for: descriptor) == "pending-secret")
			try store.deleteAll()
		} catch {
			Issue.record("secret after commit failed: \(error)")
		}
	}

	@Test
	func pendingCredentialIsDiscardedAfterFailure() throws {
		let service = "Groves.Tests.\(UUID().uuidString)"
		let store = makeTestCredentialStore(service: service)
		let descriptor = GitCredentialDescriptor(kind: .ssh, host: "SSH Key", account: "id_rsa")

		do {
			try store.savePending(secret: "discarded-secret", for: descriptor, operationID: "failure")
		} catch {
			Issue.record("savePending failed: \(error)")
			return
		}
		do {
			try store.discardPending(operationID: "failure")
		} catch {
			Issue.record("discardPending failed: \(error)")
			return
		}
		do {
			try store.commitPending(operationID: "failure")
			#expect(try store.secret(for: descriptor) == nil)
		} catch {
			Issue.record("commit after discard failed: \(error)")
		}
	}

	@Test
	func currentQueriesUseSharedDataProtectionAccessGroup() throws {
		let client = GitCredentialSecurityClientStub()
		let store = makeTestCredentialStore(securityClient: client)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		try store.save(secret: "secret", for: descriptor)

		guard case .update(let updateQuery, let attributes) = client.recordedCalls.first,
			case .add(let addQuery) = client.recordedCalls.dropFirst().first
		else {
			Issue.record("save must try update before add")
			return
		}
		assertCurrentStorage(updateQuery)
		assertCurrentStorage(addQuery)
		#expect(
			attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock
				as String)
		#expect(
			addQuery[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock
				as String)
	}

	@Test
	func secretFallsBackToLegacyWithoutCurrentStorageSelectors() throws {
		let client = GitCredentialSecurityClientStub()
		let store = makeTestCredentialStore(securityClient: client)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		#expect(try store.secret(for: descriptor) == nil)

		let copyQueries = client.recordedCalls.compactMap { call -> [String: Any]? in
			guard case .copyMatching(let query) = call else { return nil }
			return query
		}
		#expect(copyQueries.count == 2)
		if copyQueries.count == 2 {
			assertCurrentStorage(copyQueries[0])
			#expect(copyQueries[1][kSecUseDataProtectionKeychain as String] == nil)
			#expect(copyQueries[1][kSecAttrAccessGroup as String] == nil)
		}
	}

	@Test
	func missingAccessGroupUsesUnscopedKeychainStorage() throws {
		let client = GitCredentialSecurityClientStub()
		let store = GitCredentialStore(
			service: "Groves.Tests.\(UUID().uuidString)",
			securityClient: client,
			accessGroupResolver: { throw GitCredentialStoreError.missingAccessGroup }
		)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		try store.save(secret: "secret", for: descriptor)

		guard case .update(let query, _) = client.recordedCalls.first else {
			Issue.record("save must query the unscoped store first")
			return
		}
		#expect(query[kSecUseDataProtectionKeychain as String] == nil)
		#expect(query[kSecAttrAccessGroup as String] == nil)
		#expect(try store.secret(for: descriptor) == "secret")
	}

	@Test(arguments: [
		(errSecAuthFailed, GitCredentialStoreOperation.update),
		(errSecInteractionNotAllowed, GitCredentialStoreOperation.update),
	])
	func updateErrorPreservesStageAndStatus(
		status: OSStatus,
		operation: GitCredentialStoreOperation
	) {
		let client = GitCredentialSecurityClientStub()
		client.nextUpdateStatus = status
		let store = makeTestCredentialStore(securityClient: client)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		assertKeychainError(operation: operation, status: status) {
			try store.save(secret: "secret", for: descriptor)
		}
	}

	@Test
	func addErrorPreservesStageAndStatus() {
		let client = GitCredentialSecurityClientStub()
		client.nextUpdateStatus = errSecItemNotFound
		client.nextAddStatus = errSecAuthFailed
		let store = makeTestCredentialStore(securityClient: client)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		assertKeychainError(operation: .add, status: errSecAuthFailed) {
			try store.save(secret: "secret", for: descriptor)
		}
	}

	@Test
	func copyAndDeleteErrorsPreserveStageAndStatus() {
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		let copyClient = GitCredentialSecurityClientStub()
		copyClient.nextCopyStatus = errSecInteractionNotAllowed
		let copyStore = makeTestCredentialStore(securityClient: copyClient)
		assertKeychainError(operation: .copySecret, status: errSecInteractionNotAllowed) {
			_ = try copyStore.secret(for: descriptor)
		}

		let deleteClient = GitCredentialSecurityClientStub()
		deleteClient.nextDeleteStatus = errSecAuthFailed
		let deleteStore = makeTestCredentialStore(securityClient: deleteClient)
		assertKeychainError(operation: .delete, status: errSecAuthFailed) {
			try deleteStore.delete(descriptor)
		}
	}

	@Test
	func saveDecisionDefaultsToEnabledAndIsConsumed() {
		let suiteName = "Groves.Tests.\(UUID().uuidString)"
		let store = GitCredentialSaveDecisionStore(suiteName: suiteName)

		#expect(store.consumeShouldSave(operationID: "default"))
		store.setShouldSave(false, operationID: "disabled")
		#expect(store.consumeShouldSave(operationID: "disabled") == false)
		#expect(store.consumeShouldSave(operationID: "disabled"))
	}
}

private func assertCurrentStorage(_ query: [String: Any]) {
	#expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
	#expect(
		query[kSecAttrAccessGroup as String] as? String
			== "TESTTEAM.io.github.francisswiftbuilder.Groves.GitCredential"
	)
}

private func assertKeychainError(
	operation: GitCredentialStoreOperation,
	status: OSStatus,
	_ body: () throws -> Void
) {
	do {
		try body()
		Issue.record("expected Keychain error")
	} catch GitCredentialStoreError.keychain(
		let actualOperation,
		let actualStatus,
		_
	) {
		#expect(actualOperation == operation)
		#expect(actualStatus == status)
	} catch {
		Issue.record("unexpected error: \(error)")
	}
}
