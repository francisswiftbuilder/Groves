import Foundation
import Testing

@testable import CoreGitCredential

@Suite(.serialized)
struct GitCredentialTransactionTests {
	@Test
	func retryReplacesPendingSecretForSameDescriptor() throws {
		let store = makeTestCredentialStore()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		defer { try? store.deleteAll() }

		try store.savePending(secret: "first-attempt", for: descriptor, operationID: "retry")
		try store.savePending(secret: "second-attempt", for: descriptor, operationID: "retry")
		try store.commitPending(operationID: "retry")

		#expect(try store.secret(for: descriptor) == "second-attempt")
	}

	@Test
	func pendingCredentialsAreScopedToTheirOperation() throws {
		let store = makeTestCredentialStore()
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
		let store = makeTestCredentialStore()
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

	@Test
	func legacyHTTPSCredentialMigratesBeforeTheLegacyItemIsDeleted() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let client = GitCredentialSecurityClientStub()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		try client.insert(
			secret: "legacy-token",
			descriptor: descriptor,
			service: service,
			storageIsCurrent: false
		)
		let store = makeTestCredentialStore(service: service, securityClient: client)

		#expect(try store.secret(for: descriptor) == "legacy-token")
		#expect(client.contains(account: descriptor.id, service: service, storageIsCurrent: true))
		#expect(
			client.contains(account: descriptor.id, service: service, storageIsCurrent: false) == false)
		let migrationCalls = client.recordedCalls
		let addIndex = migrationCalls.firstIndex { call in
			if case .add = call { return true }
			return false
		}
		let deleteIndex = migrationCalls.firstIndex { call in
			if case .delete = call { return true }
			return false
		}
		#expect(addIndex != nil)
		#expect(deleteIndex != nil)
		if let addIndex, let deleteIndex {
			#expect(addIndex < deleteIndex)
		}
	}

	@Test
	func failedMigrationPreservesTheLegacyCredential() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let client = GitCredentialSecurityClientStub()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		try client.insert(
			secret: "legacy-token",
			descriptor: descriptor,
			service: service,
			storageIsCurrent: false
		)
		client.nextUpdateStatus = errSecItemNotFound
		client.nextAddStatus = errSecAuthFailed
		let store = makeTestCredentialStore(service: service, securityClient: client)

		#expect(throws: GitCredentialStoreError.self) {
			_ = try store.secret(for: descriptor)
		}
		#expect(client.contains(account: descriptor.id, service: service, storageIsCurrent: false))
		#expect(
			client.contains(account: descriptor.id, service: service, storageIsCurrent: true) == false)
	}

	@Test
	func malformedItemDoesNotBlockValidCredentials() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let client = GitCredentialSecurityClientStub()
		let diagnostics = DiagnosticRecorder()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		try client.insert(
			secret: "token",
			descriptor: descriptor,
			service: service,
			storageIsCurrent: true
		)
		client.insertMalformed(account: "broken", service: service, storageIsCurrent: true)
		let store = makeTestCredentialStore(
			service: service,
			securityClient: client,
			diagnosticHandler: diagnostics.record
		)

		#expect(try store.descriptors() == [descriptor])
		#expect(
			diagnostics.values.contains(
				GitCredentialStoreError.invalidDescriptor.diagnosticDescription
			)
		)
	}

	@Test
	func commitResolvesEveryPendingSecretBeforeWritingPermanentCredentials() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let pendingService = service + ".pending"
		let client = GitCredentialSecurityClientStub()
		let first = GitCredentialDescriptor(kind: .https, host: "github.com", account: "first")
		let second = GitCredentialDescriptor(kind: .https, host: "github.com", account: "second")
		try client.insert(
			secret: "first-token",
			descriptor: first,
			account: "operation|\(first.id)",
			service: pendingService,
			storageIsCurrent: true
		)
		try client.insert(
			secret: nil,
			descriptor: second,
			account: "operation|\(second.id)",
			service: pendingService,
			storageIsCurrent: true
		)
		let store = makeTestCredentialStore(service: service, securityClient: client)

		#expect(throws: GitCredentialStoreError.self) {
			try store.commitPending(operationID: "operation")
		}
		#expect(try store.secret(for: first) == nil)
		#expect(
			client.contains(
				account: "operation|\(first.id)", service: pendingService, storageIsCurrent: true))
	}

	@Test
	func staleCleanupUsesUpdatedTimestampAndPreservesCurrentOperation() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let pendingService = service + ".pending"
		let now = Date(timeIntervalSince1970: 2_000_000)
		let old = now.addingTimeInterval(-(25 * 60 * 60))
		let recent = now.addingTimeInterval(-(60 * 60))
		let client = GitCredentialSecurityClientStub()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		try client.insert(
			secret: "recent",
			descriptor: descriptor,
			account: "recent|\(descriptor.id)",
			service: pendingService,
			storageIsCurrent: true,
			creationDate: old,
			updatedAt: recent
		)
		try client.insert(
			secret: "stale",
			descriptor: descriptor,
			account: "stale|\(descriptor.id)",
			service: pendingService,
			storageIsCurrent: true,
			creationDate: old
		)
		try client.insert(
			secret: "current",
			descriptor: descriptor,
			account: "current|\(descriptor.id)",
			service: pendingService,
			storageIsCurrent: true,
			creationDate: old
		)
		try client.insert(
			secret: "unknown-age",
			descriptor: descriptor,
			account: "unknown|\(descriptor.id)",
			service: pendingService,
			storageIsCurrent: true,
			creationDate: nil
		)
		let store = makeTestCredentialStore(
			service: service,
			securityClient: client,
			now: { now }
		)

		try store.savePending(secret: "replacement", for: descriptor, operationID: "current")
		try store.savePending(secret: "other", for: descriptor, operationID: "other")

		#expect(
			client.contains(
				account: "recent|\(descriptor.id)", service: pendingService, storageIsCurrent: true))
		#expect(
			client.contains(
				account: "stale|\(descriptor.id)", service: pendingService, storageIsCurrent: true) == false
		)
		#expect(
			client.contains(
				account: "current|\(descriptor.id)", service: pendingService, storageIsCurrent: true))
		#expect(
			client.contains(
				account: "unknown|\(descriptor.id)", service: pendingService, storageIsCurrent: true)
				== false)
	}

	@Test
	func legacyPendingCredentialIsDiscardedWithoutBeingCommitted() throws {
		let service = "Trees.Tests.\(UUID().uuidString)"
		let pendingService = service + ".pending"
		let client = GitCredentialSecurityClientStub()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "trees")
		let account = "legacy|\(descriptor.id)"
		try client.insert(
			secret: "legacy-pending",
			descriptor: descriptor,
			account: account,
			service: pendingService,
			storageIsCurrent: false
		)
		let store = makeTestCredentialStore(service: service, securityClient: client)

		try store.commitPending(operationID: "legacy")

		#expect(try store.secret(for: descriptor) == nil)
		#expect(client.contains(account: account, service: pendingService, storageIsCurrent: false))

		try store.discardPending(operationID: "legacy")

		#expect(
			client.contains(account: account, service: pendingService, storageIsCurrent: false) == false)
	}
}
