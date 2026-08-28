import Foundation

@MainActor
public struct GitCredentialPromptCoordinator {
	private let store: GitCredentialStore
	private let decisionStore: GitCredentialSaveDecisionStore
	private let presenter: any GitCredentialPromptPresenting

	public init(
		store: GitCredentialStore,
		decisionStore: GitCredentialSaveDecisionStore,
		presenter: any GitCredentialPromptPresenting
	) {
		self.store = store
		self.decisionStore = decisionStore
		self.presenter = presenter
	}

	public func value(forPrompt prompt: String, operationID: String?) throws -> String {
		let kind = GitCredentialPromptKind(prompt: prompt)
		let descriptor = GitCredentialDescriptor.sshKey(forPassphrasePrompt: prompt)
		if kind == .secret, let descriptor, let secret = try store.secret(for: descriptor) {
			return secret
		}

		let answer = try presenter.presentPrompt(prompt, kind: kind)
		guard let operationID, operationID.isEmpty == false else { return answer.value }
		decisionStore.setShouldSave(answer.shouldSave, operationID: operationID)
		guard kind == .secret, answer.shouldSave, let descriptor else { return answer.value }
		try store.savePending(secret: answer.value, for: descriptor, operationID: operationID)
		return answer.value
	}
}
