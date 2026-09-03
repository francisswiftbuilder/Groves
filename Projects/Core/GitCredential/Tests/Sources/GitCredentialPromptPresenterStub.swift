import Foundation

@testable import CoreGitCredential

@MainActor
final class GitCredentialPromptPresenterStub: GitCredentialPromptPresenting {
	private let answer: GitCredentialPromptAnswer?
	private(set) var presentedPrompts: [String] = []
	private(set) var presentedKinds: [GitCredentialPromptKind] = []

	init(answer: GitCredentialPromptAnswer?) {
		self.answer = answer
	}

	func presentPrompt(
		_ prompt: String,
		kind: GitCredentialPromptKind
	) throws -> GitCredentialPromptAnswer {
		presentedPrompts.append(prompt)
		presentedKinds.append(kind)
		guard let answer else { throw CancellationError() }
		return answer
	}
}
