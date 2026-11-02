import Darwin
import Foundation
import Testing

@testable import CoreGitCredential

struct GitCredentialBrokerTests {
	private final class Context: Sendable {
		let store: GitCredentialStore
		let identifier: String
		let broker: GitCredentialBroker
		let client: GitCredentialBrokerClient

		init(trustClient: Bool = true, trustServer: Bool = true) throws {
			let store = makeTestCredentialStore()
			let identifier = UUID().uuidString
			self.store = store
			self.identifier = identifier
			let helper = GitCredentialHelper(
				store: store,
				decisionStore: GitCredentialSaveDecisionStore(suiteName: "Groves.Tests.\(identifier)"))
			let broker = try GitCredentialBroker(operationID: identifier, helper: helper) { peer in
				trustClient && peer.processIdentifier == getpid()
			}
			self.broker = broker
			client = GitCredentialBrokerClient(socketPath: broker.socketPath, operationID: identifier) {
				peer in
				trustServer && peer.processIdentifier == getpid()
			}
		}

		deinit {
			broker.stop()
			try? store.deleteAll()
			UserDefaults(suiteName: "Groves.Tests.\(identifier)")?.removePersistentDomain(
				forName: "Groves.Tests.\(identifier)")
		}
	}

	@Test
	func aSavedAccountCanBeReadThroughTheBroker() throws {
		let context = try Context()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try context.store.save(secret: "parent-only-secret", for: descriptor)

		let value = try context.client.credential(
			operation: .get, input: "protocol=https\nhost=github.com\n\n")

		#expect(value == "password=parent-only-secret\nusername=groves\n\n")
		#expect(!context.broker.socketPath.contains("parent-only-secret"))
		let names = try FileManager.default.contentsOfDirectory(
			atPath: URL(fileURLWithPath: context.broker.socketPath).deletingLastPathComponent().path)
		#expect(names == ["socket"])
	}

	@Test(arguments: [false, true])
	func savingHonorsThePromptDecisionAndWaitsForGitSuccess(shouldSave: Bool) throws {
		let context = try Context()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try context.client.setShouldSave(shouldSave)

		_ = try context.client.credential(
			operation: .store,
			input: "protocol=https\nhost=github.com\nusername=groves\npassword=entered-secret\n\n")
		_ = try context.client.credential(
			operation: .store,
			input: "protocol=https\nhost=github.com\nusername=groves\npassword=entered-secret\n\n")

		#expect(try context.store.secret(for: descriptor) == nil)
		context.broker.stop()
		try context.store.commitPending(operationID: context.identifier)
		#expect(try context.store.secret(for: descriptor) == (shouldSave ? "entered-secret" : nil))
	}

	@Test
	func aDifferentOperationCannotReadTheAccount() throws {
		let context = try Context()
		let client = GitCredentialBrokerClient(
			socketPath: context.broker.socketPath, operationID: "stale"
		) { _ in true }

		#expect(throws: GitCredentialBrokerError.self) {
			try client.credential(operation: .get, input: "protocol=https\nhost=github.com\n\n")
		}
	}

	@Test(arguments: [false, true])
	func untrustedPeersCannotReadOrStoreCredentials(rejectServer: Bool) throws {
		let context = try Context(trustClient: rejectServer, trustServer: !rejectServer)
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")

		#expect(throws: GitCredentialBrokerError.self) {
			try context.client.credential(
				operation: .store,
				input: "protocol=https\nhost=github.com\nusername=groves\npassword=not-authorized\n\n")
		}

		context.broker.stop()
		try context.store.commitPending(operationID: context.identifier)
		#expect(try context.store.secret(for: descriptor) == nil)
	}

	@Test
	func stoppingRemovesTheEndpointAndCanBeRepeated() throws {
		let context = try Context()
		let path = context.broker.socketPath
		let attributes = try FileManager.default.attributesOfItem(atPath: path)
		#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
		let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
		let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
		#expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)

		context.broker.stop()
		context.broker.stop()

		#expect(!FileManager.default.fileExists(atPath: directory.path))
		#expect(throws: GitCredentialBrokerError.self) {
			try context.client.credential(operation: .get, input: "protocol=https\nhost=github.com\n\n")
		}
	}

	@Test
	func oversizedMessagesAreRejectedWithoutReadingTheirBody() throws {
		let context = try Context()
		let descriptor = try GitCredentialSocket.make()
		defer { close(descriptor) }
		try connect(descriptor, to: context.broker.socketPath)
		var count = UInt32(GitCredentialSocket.maximumMessageSize + 1).bigEndian
		let sent = withUnsafeBytes(of: &count) { send(descriptor, $0.baseAddress, $0.count, 0) }
		#expect(sent == 4)

		let response = try GitCredentialSocket.read(
			GitCredentialBrokerMessage.Response.self, from: descriptor)

		guard case .failure(let diagnostic) = response else {
			Issue.record("Expected oversized frame rejection")
			return
		}
		#expect(diagnostic.contains("invalid-message"))
	}

	@Test
	func simultaneousCredentialRequestsUseIndependentConnections() async throws {
		let context = try Context()
		let descriptor = GitCredentialDescriptor(kind: .https, host: "github.com", account: "groves")
		try context.store.save(secret: "shared-secret", for: descriptor)

		let values = try await withThrowingTaskGroup(of: String?.self) { group in
			for _ in 0..<16 {
				group.addTask {
					try await withCheckedThrowingContinuation { continuation in
						Thread.detachNewThread {
							continuation.resume(
								with: Result {
									try context.client.credential(
										operation: .get, input: "protocol=https\nhost=github.com\n\n")
								})
						}
					}
				}
			}
			var values: [String?] = []
			for try await value in group { values.append(value) }
			return values
		}

		#expect(values.count == 16)
		#expect(values.allSatisfy { $0 == "password=shared-secret\nusername=groves\n\n" })
	}

	@Test
	func stoppingInterruptsAnIncompleteRequest() async throws {
		let context = try Context()
		let descriptor = try GitCredentialSocket.make()
		defer { close(descriptor) }
		try connect(descriptor, to: context.broker.socketPath)
		var expectedBytes = UInt32(100).bigEndian
		_ = withUnsafeBytes(of: &expectedBytes) { send(descriptor, $0.baseAddress, $0.count, 0) }
		var timeout = timeval(tv_sec: 1, tv_usec: 0)
		try #require(
			setsockopt(
				descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout,
				socklen_t(MemoryLayout.size(ofValue: timeout))) == 0)
		let start = ContinuousClock.now

		context.broker.stop()

		var byte: UInt8 = 0
		let count = recv(descriptor, &byte, 1, 0)
		#expect(count <= 0)
		#expect(ContinuousClock.now - start < .seconds(1))
		#expect(!FileManager.default.fileExists(atPath: context.broker.socketPath))
	}

	private func connect(_ descriptor: Int32, to path: String) throws {
		let result = try GitCredentialSocket.withAddress(path: path) {
			Darwin.connect(descriptor, $0, $1)
		}
		try #require(result == 0)
	}
}
