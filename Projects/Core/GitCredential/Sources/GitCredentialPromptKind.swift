import Foundation

public enum GitCredentialPromptKind: Hashable, Sendable {
	case username
	case secret
	case hostTrust

	public init(prompt: String) {
		let lowercased = prompt.lowercased()
		if lowercased.contains("authenticity of host") || lowercased.contains("fingerprint") {
			self = .hostTrust
		} else if lowercased.contains("username") || lowercased.contains("user name") {
			self = .username
		} else {
			self = .secret
		}
	}
}
