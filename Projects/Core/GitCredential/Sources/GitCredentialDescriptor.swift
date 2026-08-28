import CryptoKit
import Foundation

public struct GitCredentialDescriptor: Codable, Hashable, Identifiable, Sendable {
	public let kind: GitCredentialKind
	public let host: String
	public let account: String
	public let scope: String?

	public var id: String {
		guard let scope, !scope.isEmpty else {
			return "\(kind.rawValue)|\(host)|\(account)"
		}
		return "\(kind.rawValue)|\(host)|\(account)|\(scope)"
	}

	public var legacyIdentifier: String {
		"\(kind.rawValue)|\(host)|\(account)"
	}

	public init(kind: GitCredentialKind, host: String, account: String, scope: String? = nil) {
		self.kind = kind
		self.host = host
		self.account = account
		self.scope = scope
	}

	public static func sshKey(at path: String) -> GitCredentialDescriptor {
		let keyURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
			.standardizedFileURL
			.resolvingSymlinksInPath()
		return GitCredentialDescriptor(
			kind: .ssh,
			host: "SSH Key",
			account: keyURL.lastPathComponent,
			scope: scope(forCanonicalPath: keyURL.path)
		)
	}

	public static func sshKey(forPassphrasePrompt prompt: String) -> GitCredentialDescriptor? {
		guard prompt.localizedCaseInsensitiveContains("passphrase"),
			let firstQuote = prompt.firstIndex(of: "'"),
			let secondQuote = prompt[prompt.index(after: firstQuote)...].firstIndex(of: "'")
		else { return nil }
		let path = String(prompt[prompt.index(after: firstQuote)..<secondQuote])
		guard path.isEmpty == false else { return nil }
		return .sshKey(at: path)
	}

	private static func scope(forCanonicalPath path: String) -> String {
		SHA256.hash(data: Data(path.utf8))
			.prefix(8)
			.map { String(format: "%02x", $0) }
			.joined()
	}
}
