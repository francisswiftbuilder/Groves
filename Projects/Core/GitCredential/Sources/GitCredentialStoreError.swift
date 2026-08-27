import Foundation

public enum GitCredentialStoreError: LocalizedError, Sendable {
	case keychain(Int32)
	case invalidDescriptor

	public var errorDescription: String? {
		switch self {
		case .keychain(let status):
			return "Keychain operation failed with status \(status)."
		case .invalidDescriptor:
			return "The stored credential descriptor is invalid."
		}
	}
}
