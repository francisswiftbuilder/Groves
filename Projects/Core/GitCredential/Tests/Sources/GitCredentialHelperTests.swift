import Foundation
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialHelperTests {
	@Test
	func storeKeepsSecretPendingUntilTheOperationSucceeds() throws {
		let store = makeTestCredentialStore()
		let decisionStore = GitCredentialSaveDecisionStore(
			suiteName: "Groves.Tests.\(UUID().uuidString)")
		let helper = GitCredentialHelper(store: store, decisionStore: decisionStore)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		defer { try? store.deleteAll() }

		decisionStore.setShouldSave(true, operationID: "operation")
		_ = try helper.handle(
			operation: .store,
			input: "protocol=https\nhost=github.com\nusername=groves\npassword=token\n",
			operationID: "operation"
		)

		#expect(try store.secret(for: descriptor) == nil)

		try store.commitPending(operationID: "operation")

		#expect(try store.secret(for: descriptor) == "token")
	}

	@Test
	func storeIsSkippedWhenSavingIsDeclinedOrUnattributed() throws {
		let store = makeTestCredentialStore()
		let decisionStore = GitCredentialSaveDecisionStore(
			suiteName: "Groves.Tests.\(UUID().uuidString)")
		let helper = GitCredentialHelper(store: store, decisionStore: decisionStore)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		let input = "protocol=https\nhost=github.com\nusername=groves\npassword=token\n"
		defer { try? store.deleteAll() }

		decisionStore.setShouldSave(false, operationID: "declined")
		_ = try helper.handle(operation: .store, input: input, operationID: "declined")
		try store.commitPending(operationID: "declined")

		#expect(try store.secret(for: descriptor) == nil)

		_ = try helper.handle(operation: .store, input: input, operationID: nil)
		try store.commitPending(operationID: "")

		#expect(try store.secret(for: descriptor) == nil)
	}

	@Test
	func getReturnsStoredCredentialAndEraseRemovesIt() throws {
		let store = makeTestCredentialStore()
		let helper = GitCredentialHelper(
			store: store,
			decisionStore: GitCredentialSaveDecisionStore(suiteName: "Groves.Tests.\(UUID().uuidString)")
		)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		defer { try? store.deleteAll() }
		try store.save(secret: "token", for: descriptor)

		let response = try helper.handle(
			operation: .get,
			input: "protocol=https\nhost=github.com\n",
			operationID: "operation"
		)

		#expect(response == "password=token\nusername=groves\n\n")

		_ = try helper.handle(
			operation: .erase,
			input: "protocol=https\nhost=github.com\n",
			operationID: "operation"
		)

		#expect(try store.secret(for: descriptor) == nil)
	}

	@Test
	func sshKeysWithTheSameNameAreDistinctCredentials() throws {
		let store = makeTestCredentialStore()
		let personal = GitCredentialDescriptor.sshKey(at: "/Users/groves/.ssh/id_ed25519")
		let work = GitCredentialDescriptor.sshKey(at: "/Users/groves/work/.ssh/id_ed25519")
		defer { try? store.deleteAll() }

		#expect(personal.account == "id_ed25519")
		#expect(work.account == "id_ed25519")
		#expect(personal.id != work.id)

		try store.save(secret: "personal-passphrase", for: personal)
		try store.save(secret: "work-passphrase", for: work)

		#expect(try store.secret(for: personal) == "personal-passphrase")
		#expect(try store.secret(for: work) == "work-passphrase")
	}

	@Test
	func legacySSHCredentialIsNotAssignedToAnAmbiguousPath() throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor.sshKey(at: "/Users/groves/.ssh/id_rsa")
		let legacy = GitCredentialDescriptor(kind: .ssh, host: "SSH Key", account: "id_rsa")
		defer { try? store.deleteAll() }
		try store.save(secret: "legacy-passphrase", for: legacy)

		#expect(try store.secret(for: descriptor) == nil)
		#expect(try store.secret(for: legacy) == "legacy-passphrase")
		#expect(try store.descriptors() == [legacy])
	}
}
