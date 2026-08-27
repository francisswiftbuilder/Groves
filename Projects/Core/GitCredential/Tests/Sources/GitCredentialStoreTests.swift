import Foundation
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialStoreTests {
	@Test
	func pendingCredentialCommitsOnlyAfterSuccess() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let store = GitCredentialStore(service: service)
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
		let service = "Trees.Tests.\(UUID().uuidString)"
		let store = GitCredentialStore(service: service)
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
	func saveDecisionDefaultsToEnabledAndIsConsumed() {
		let suiteName = "Trees.Tests.\(UUID().uuidString)"
		let store = GitCredentialSaveDecisionStore(suiteName: suiteName)

		#expect(store.consumeShouldSave(operationID: "default"))
		store.setShouldSave(false, operationID: "disabled")
		#expect(store.consumeShouldSave(operationID: "disabled") == false)
		#expect(store.consumeShouldSave(operationID: "disabled"))
	}
}
