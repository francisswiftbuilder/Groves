import Foundation

public struct GitCredentialDescriptor: Codable, Hashable, Identifiable, Sendable {
	public let kind: GitCredentialKind
	public let host: String
	public let account: String

	public var id: String {
		"\(kind.rawValue)|\(host)|\(account)"
	}

	public init(kind: GitCredentialKind, host: String, account: String) {
		self.kind = kind
		self.host = host
		self.account = account
	}
}
