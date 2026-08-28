import Foundation

@MainActor
public protocol GitCredentialPromptPresenting {
	func presentPrompt(
		_ prompt: String,
		kind: GitCredentialPromptKind
	) throws -> GitCredentialPromptAnswer
}
