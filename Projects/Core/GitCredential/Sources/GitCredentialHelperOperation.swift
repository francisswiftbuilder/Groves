import Foundation

public enum GitCredentialHelperOperation: String, Codable, Sendable {
	case get
	case store
	case erase
}
