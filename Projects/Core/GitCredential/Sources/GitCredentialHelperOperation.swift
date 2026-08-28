import Foundation

public enum GitCredentialHelperOperation: String, Sendable {
	case get
	case store
	case erase
}
