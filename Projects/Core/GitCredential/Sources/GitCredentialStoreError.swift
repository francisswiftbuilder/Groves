import Foundation
import Security

public enum GitCredentialStoreError: LocalizedError, Sendable {
	case keychain(operation: GitCredentialStoreOperation, status: OSStatus, message: String)
	case missingAccessGroup
	case invalidDescriptor
	case missingPendingSecret
	case migrationVerificationFailed

	public init(operation: GitCredentialStoreOperation, status: OSStatus) {
		let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
		self = .keychain(operation: operation, status: status, message: message)
	}

	public var diagnosticDescription: String {
		switch self {
		case .keychain(let operation, let status, let message):
			return "stage=\(operation.rawValue) status=\(status) message=\(message)"
		case .missingAccessGroup:
			return
				"stage=\(GitCredentialStoreOperation.resolveAccessGroup.rawValue) status=missing-entitlement"
		case .invalidDescriptor:
			return "stage=\(GitCredentialStoreOperation.decodeDescriptor.rawValue) status=invalid-data"
		case .missingPendingSecret:
			return
				"stage=\(GitCredentialStoreOperation.copySecret.rawValue) status=missing-pending-secret"
		case .migrationVerificationFailed:
			return
				"stage=\(GitCredentialStoreOperation.verifyMigration.rawValue) status=missing-migrated-item"
		}
	}

	public var errorDescription: String? {
		switch self {
		case .keychain:
			return "Keychain operation failed (\(diagnosticDescription))."
		case .missingAccessGroup:
			return "The signed application does not contain the Groves Keychain access group."
		case .invalidDescriptor:
			return "The stored credential descriptor is invalid."
		case .missingPendingSecret:
			return "The pending credential does not contain a secret."
		case .migrationVerificationFailed:
			return "The migrated credential could not be verified."
		}
	}
}
