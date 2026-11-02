import Foundation

enum GitCredentialBrokerMessage {
	struct Request: Codable, Sendable {
		enum Action: Codable, Sendable {
			case check
			case credential(GitCredentialHelperOperation, String)
			case saveDecision(Bool)
		}

		let operationID: String
		let action: Action
	}

	enum Response: Codable, Sendable {
		case success(String?)
		case failure(String)
	}
}
