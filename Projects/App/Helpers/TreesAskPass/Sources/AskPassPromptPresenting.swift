import Foundation

@MainActor
protocol AskPassPromptPresenting {
	func presentPrompt(_ prompt: String, kind: AskPassPromptKind) throws -> AskPassPromptResult
}
