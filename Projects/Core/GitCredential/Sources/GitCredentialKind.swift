import Foundation

public enum GitCredentialKind: String, Codable, Hashable, Sendable {
	case https
	case ssh
}
