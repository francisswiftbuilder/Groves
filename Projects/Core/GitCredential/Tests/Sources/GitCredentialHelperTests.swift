import Foundation
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialHelperTests {
	@Test(arguments: ["github.com", "GitHub.com:443"])
	func theSelectedAccountIsUsedInsteadOfAnAlphabeticalOrSuppliedUsername(host: String) throws {
		let store = makeTestCredentialStore()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "alice")
		let selected = GitCredentialDescriptor(kind: .https, host: "github.com", account: "zoe")
		try store.save(secret: "alice-token", for: first)
		try store.save(secret: "zoe-token", for: selected)
		let helper = try GitCredentialHelper(store: store).selectingGitHubAccount(selected.account)

		let response = try helper.handle(
			operation: .get, input: "protocol=https\nhost=\(host)\nusername=alice\n\n", operationID: nil)

		#expect(response == "password=zoe-token\nusername=zoe\n\n")
	}

	@Test
	func anOperationKeepsItsAccountWhenAnotherAccountIsAddedOrSelected() throws {
		let store = makeTestCredentialStore()
		let original = GitCredentialDescriptor(kind: .https, host: "github.com", account: "original")
		let added = GitCredentialDescriptor(kind: .https, host: "github.com", account: "added")
		try store.save(secret: "original-token", for: original)
		let originalHelper = try GitCredentialHelper(store: store).selectingGitHubAccount(nil)
		try store.save(secret: "added-token", for: added)
		let addedHelper = try GitCredentialHelper(store: store).selectingGitHubAccount(added.account)
		let input = "protocol=https\nhost=github.com\n\n"

		#expect(
			try originalHelper.handle(operation: .get, input: input, operationID: nil)
				== "password=original-token\nusername=original\n\n")
		#expect(
			try addedHelper.handle(operation: .get, input: input, operationID: nil)
				== "password=added-token\nusername=added\n\n")
	}

	@Test
	func anUnconnectedOperationDoesNotBorrowAnAccountConnectedAfterItStarted() throws {
		let store = makeTestCredentialStore()
		let helper = try GitCredentialHelper(store: store).selectingGitHubAccount(nil)
		let added = GitCredentialDescriptor(kind: .https, host: "github.com", account: "added")
		try store.save(secret: "added-token", for: added)
		let input = "protocol=https\nhost=github.com\n\n"

		#expect(throws: GitHubAccountSelectionError.self) {
			try helper.handle(operation: .get, input: input, operationID: nil)
		}
		_ = try helper.handle(operation: .erase, input: input, operationID: nil)
		#expect(try store.secret(for: added) == "added-token")
	}

	@Test(arguments: [nil, "removed"] as [String?])
	func ambiguousOrMissingSelectionsNeverFallBackToAnotherAccount(selection: String?) throws {
		let store = makeTestCredentialStore()
		for account in ["alice", "zoe"] {
			try store.save(
				secret: "\(account)-token",
				for: GitCredentialDescriptor(kind: .https, host: "github.com", account: account))
		}
		let helper = try GitCredentialHelper(store: store).selectingGitHubAccount(selection)

		#expect(throws: GitHubAccountSelectionError.self) {
			try helper.handle(
				operation: .get, input: "protocol=https\nhost=github.com\nusername=alice\n\n",
				operationID: nil)
		}
		#expect(try store.descriptors().count == 2)
	}

	@Test
	func rejectingACredentialRemovesOnlyTheOperationAccount() throws {
		let store = makeTestCredentialStore()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "alice")
		let selected = GitCredentialDescriptor(kind: .https, host: "github.com", account: "zoe")
		try store.save(secret: "alice-token", for: first)
		try store.save(secret: "zoe-token", for: selected)
		let helper = try GitCredentialHelper(store: store).selectingGitHubAccount(selected.account)

		_ = try helper.handle(
			operation: .erase, input: "protocol=https\nhost=github.com\n\n", operationID: nil)

		#expect(try store.secret(for: first) == "alice-token")
		#expect(try store.secret(for: selected) == nil)
		#expect(throws: GitHubAccountSelectionError.self) {
			try helper.handle(
				operation: .get, input: "protocol=https\nhost=github.com\n\n", operationID: nil)
		}
	}

	@Test
	func anUnattributedRejectionCannotDeleteMultipleGitHubAccounts() throws {
		let store = makeTestCredentialStore()
		for account in ["alice", "zoe"] {
			try store.save(
				secret: "\(account)-token",
				for: GitCredentialDescriptor(kind: .https, host: "github.com", account: account))
		}

		#expect(throws: GitHubAccountSelectionError.self) {
			try GitCredentialHelper(store: store).handle(
				operation: .erase, input: "protocol=https\nhost=github.com\n\n", operationID: nil)
		}
		#expect(try store.descriptors().count == 2)
	}

	@Test
	func storingAMismatchedUsernameCannotReplaceEitherSavedToken() throws {
		let store = makeTestCredentialStore()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "alice")
		let selected = GitCredentialDescriptor(kind: .https, host: "github.com", account: "zoe")
		try store.save(secret: "alice-token", for: first)
		try store.save(secret: "zoe-token", for: selected)
		let helper = try GitCredentialHelper(store: store).selectingGitHubAccount(selected.account)
		let operationID = UUID().uuidString

		#expect(throws: GitHubAccountSelectionError.self) {
			try helper.handle(
				operation: .store,
				input: "protocol=https\nhost=github.com\nusername=alice\npassword=replacement\n\n",
				operationID: operationID)
		}
		try store.commitPending(operationID: operationID)
		#expect(try store.secret(for: first) == "alice-token")
		#expect(try store.secret(for: selected) == "zoe-token")
	}

	@Test(arguments: ["github.com", "GitHub.com", "github.com:443", "GitHub.com:443"])
	func gitHubHostVariantsUseTheConnectedAccount(host: String) throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try store.save(secret: "stored-token", for: descriptor)
		let response = try GitCredentialHelper(store: store).handle(
			operation: .get, input: "protocol=https\nhost=\(host)\n\n", operationID: nil)
		#expect(response == "password=stored-token\nusername=groves\n\n")
	}

	@Test(arguments: ["github.com.evil.example", "github.com:8443", "github.com@evil.example"])
	func unrelatedHostsCannotReadTheGitHubAccount(host: String) throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try store.save(secret: "stored-token", for: descriptor)
		let response = try GitCredentialHelper(store: store).handle(
			operation: .get, input: "protocol=https\nhost=\(host)\n\n", operationID: nil)
		#expect(response == nil)
	}

	@Test
	func neverReturnsHTTPSCredentialsForAnHTTPConnection() throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try store.save(secret: "private-token", for: descriptor)
		let helper = GitCredentialHelper(store: store)

		let response = try helper.handle(
			operation: .get, input: "protocol=http\nhost=github.com\n\n", operationID: nil)

		#expect(response == nil)
		#expect(try store.secret(for: descriptor) == "private-token")
	}

	@Test
	func emptyUsernameUsesTheSavedAccount() throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try store.save(secret: "private-token", for: descriptor)
		let helper = GitCredentialHelper(store: store)

		let response = try helper.handle(
			operation: .get, input: "protocol=https\nhost=github.com\nusername=\n\n", operationID: nil)

		#expect(response == "password=private-token\nusername=groves\n\n")
	}

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
