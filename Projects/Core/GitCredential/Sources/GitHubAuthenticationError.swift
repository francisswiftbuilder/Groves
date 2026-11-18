import Foundation

public enum GitHubAuthenticationError: LocalizedError, Sendable {
	case invalidToken
	case forbidden
	case rateLimited
	case unavailable

	public var errorDescription: String? {
		switch self {
		case .invalidToken:
			return "This token is invalid or expired. Create a new GitHub token and try again."
		case .forbidden:
			return "GitHub denied this request. Check token permissions and organization approval."
		case .rateLimited:
			return "GitHub is limiting requests. Wait a moment before trying again."
		case .unavailable:
			return "GitHub could not verify the account. Check your connection and try again."
		}
	}
}
