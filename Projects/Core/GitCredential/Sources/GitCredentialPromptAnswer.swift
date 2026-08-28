import Foundation

public struct GitCredentialPromptAnswer: Hashable, Sendable {
	public let value: String
	public let shouldSave: Bool

	public init(value: String, shouldSave: Bool) {
		self.value = value
		self.shouldSave = shouldSave
	}
}
