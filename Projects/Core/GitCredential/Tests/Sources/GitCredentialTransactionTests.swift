import Foundation
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialTransactionTests {
	@Test
	func retryReplacesPendingSecretForSameDescriptor() throws {
		let store = GitCredentialStore(service: "Trees.Tests.\(UUID().uuidString)")
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		defer { try? store.deleteAll() }

		try store.savePending(secret: "first-attempt", for: descriptor, operationID: "retry")
		try store.savePending(secret: "second-attempt", for: descriptor, operationID: "retry")
		try store.commitPending(operationID: "retry")

		#expect(try store.secret(for: descriptor) == "second-attempt")
	}

	@Test
	func pendingCredentialsAreScopedToTheirOperation() throws {
		let store = GitCredentialStore(service: "Trees.Tests.\(UUID().uuidString)")
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		defer { try? store.deleteAll() }

		try store.savePending(secret: "other-operation", for: descriptor, operationID: "other")
		try store.commitPending(operationID: "current")

		#expect(try store.secret(for: descriptor) == nil)

		try store.discardPending(operationID: "other")
		try store.commitPending(operationID: "other")

		#expect(try store.secret(for: descriptor) == nil)
	}

	@Test
	func deletingAllCredentialsAlsoRemovesPendingSecrets() throws {
		let store = GitCredentialStore(service: "Trees.Tests.\(UUID().uuidString)")
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		defer { try? store.deleteAll() }

		try store.savePending(secret: "leaked-secret", for: descriptor, operationID: "abandoned")
		try store.deleteAll()
		try store.commitPending(operationID: "abandoned")

		#expect(
			try store.secret(for: descriptor) == nil,
			"deleteAll must not leave pending secrets behind"
		)
	}
}
