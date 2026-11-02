import Foundation

public enum GitCredentialBrokerError: LocalizedError, Sendable {
	case unavailable
	case invalidMessage
	case untrustedPeer
	case systemCall(String, Int32)
	case requestFailed(String)

	public var diagnosticDescription: String {
		switch self {
		case .unavailable: return "stage=credential-broker status=unavailable"
		case .invalidMessage: return "stage=credential-broker status=invalid-message"
		case .untrustedPeer: return "stage=credential-broker status=untrusted-peer"
		case .systemCall(let operation, let status):
			return "stage=credential-broker-\(operation) status=\(status)"
		case .requestFailed(let diagnostic): return diagnostic
		}
	}

	public var errorDescription: String? {
		"Groves could not complete the local authentication request (\(diagnosticDescription)). Retry the Git operation while Groves is open."
	}
}
