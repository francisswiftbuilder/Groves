import Foundation

public enum GitHubAccountSelectionError: LocalizedError, Sendable {
	case selectionRequired
	case accountUnavailable
	case accountMismatch

	public var diagnosticDescription: String {
		switch self {
		case .selectionRequired: return "stage=account-selection status=selection-required"
		case .accountUnavailable: return "stage=account-selection status=account-unavailable"
		case .accountMismatch: return "stage=account-selection status=account-mismatch"
		}
	}

	public var errorDescription: String? {
		switch self {
		case .selectionRequired:
			return "Connect or choose an active GitHub account in Settings → Accounts, then retry."
		case .accountUnavailable:
			return
				"The active GitHub account is no longer available. Reconnect it or choose another account in Settings → Accounts."
		case .accountMismatch:
			return
				"The credential does not match the active GitHub account. Choose the account in Settings → Accounts, then retry."
		}
	}
}
