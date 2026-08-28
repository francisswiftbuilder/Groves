import Foundation
import Testing

@testable import CoreGitCredential

@MainActor
@Suite(.serialized)
struct GitCredentialPromptCoordinatorTests {
	@Test
	func aStoredPassphraseIsReturnedWithoutPresentingAPrompt() throws {
		let store = makeStore()
		let presenter = GitCredentialPromptPresenterStub(
			answer: GitCredentialPromptAnswer(value: "typed", shouldSave: true)
		)
		let coordinator = makeCoordinator(store: store, presenter: presenter)
		defer { try? store.deleteAll() }
		try store.save(secret: "stored", for: .sshKey(at: "/tmp/id_ed25519"))

		let value = try coordinator.value(
			forPrompt: "Enter passphrase for key '/tmp/id_ed25519':",
			operationID: "operation"
		)

		#expect(value == "stored")
		#expect(presenter.presentedPrompts.isEmpty, "A stored secret must not prompt the user")
	}

	@Test
	func anAcceptedSecretIsOnlyReadableAfterTheOperationCommits() throws {
		let store = makeStore()
		let coordinator = makeCoordinator(
			store: store,
			presenter: GitCredentialPromptPresenterStub(
				answer: GitCredentialPromptAnswer(value: "typed", shouldSave: true)
			)
		)
		let descriptor = GitCredentialDescriptor.sshKey(at: "/tmp/id_ed25519")
		defer { try? store.deleteAll() }

		let value = try coordinator.value(
			forPrompt: "Enter passphrase for key '/tmp/id_ed25519':",
			operationID: "operation"
		)

		#expect(value == "typed")
		#expect(try store.secret(for: descriptor) == nil)

		try store.commitPending(operationID: "operation")

		#expect(try store.secret(for: descriptor) == "typed")
	}

	@Test
	func decliningToSaveKeepsTheSecretOutOfTheKeychain() throws {
		let store = makeStore()
		let decisionStore = makeDecisionStore()
		let coordinator = makeCoordinator(
			store: store,
			decisionStore: decisionStore,
			presenter: GitCredentialPromptPresenterStub(
				answer: GitCredentialPromptAnswer(value: "typed", shouldSave: false)
			)
		)
		defer { try? store.deleteAll() }

		let value = try coordinator.value(
			forPrompt: "Enter passphrase for key '/tmp/id_ed25519':",
			operationID: "operation"
		)
		try store.commitPending(operationID: "operation")

		#expect(value == "typed")
		#expect(try store.secret(for: .sshKey(at: "/tmp/id_ed25519")) == nil)
		#expect(decisionStore.consumeShouldSave(operationID: "operation") == false)
	}

	@Test
	func aPromptWithoutAnOperationIdentifierIsNeverPersisted() throws {
		let store = makeStore()
		let coordinator = makeCoordinator(
			store: store,
			presenter: GitCredentialPromptPresenterStub(
				answer: GitCredentialPromptAnswer(value: "typed", shouldSave: true)
			)
		)
		defer { try? store.deleteAll() }

		let value = try coordinator.value(
			forPrompt: "Enter passphrase for key '/tmp/id_ed25519':",
			operationID: ""
		)
		try store.commitPending(operationID: "")

		#expect(value == "typed")
		#expect(try store.secret(for: .sshKey(at: "/tmp/id_ed25519")) == nil)
	}

	@Test
	func aUsernameAnswerIsNeverStoredAsASecret() throws {
		let store = makeStore()
		let presenter = GitCredentialPromptPresenterStub(
			answer: GitCredentialPromptAnswer(value: "trees", shouldSave: true)
		)
		let coordinator = makeCoordinator(store: store, presenter: presenter)
		defer { try? store.deleteAll() }

		let value = try coordinator.value(
			forPrompt: "Username for 'https://github.com':",
			operationID: "operation"
		)
		try store.commitPending(operationID: "operation")

		#expect(value == "trees")
		#expect(presenter.presentedKinds == [.username])
		#expect(try store.descriptors().isEmpty)
	}

	@Test
	func aCancelledPromptFailsWithoutStoringAnything() throws {
		let store = makeStore()
		let coordinator = makeCoordinator(
			store: store,
			presenter: GitCredentialPromptPresenterStub(answer: nil)
		)
		defer { try? store.deleteAll() }

		#expect(throws: CancellationError.self) {
			try coordinator.value(
				forPrompt: "Enter passphrase for key '/tmp/id_ed25519':",
				operationID: "operation"
			)
		}

		try store.commitPending(operationID: "operation")

		#expect(try store.secret(for: .sshKey(at: "/tmp/id_ed25519")) == nil)
	}

	private func makeStore() -> GitCredentialStore {
		GitCredentialStore(service: "Trees.Tests.\(UUID().uuidString)")
	}

	private func makeDecisionStore() -> GitCredentialSaveDecisionStore {
		GitCredentialSaveDecisionStore(suiteName: "Trees.Tests.\(UUID().uuidString)")
	}

	private func makeCoordinator(
		store: GitCredentialStore,
		decisionStore: GitCredentialSaveDecisionStore? = nil,
		presenter: any GitCredentialPromptPresenting
	) -> GitCredentialPromptCoordinator {
		GitCredentialPromptCoordinator(
			store: store,
			decisionStore: decisionStore ?? makeDecisionStore(),
			presenter: presenter
		)
	}
}
