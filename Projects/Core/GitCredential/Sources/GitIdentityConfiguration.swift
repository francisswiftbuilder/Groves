import Foundation

public struct GitIdentityConfiguration: Codable, Equatable, Sendable {
	public var name: String
	public var email: String

	public static var defaultURL: URL {
		FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appending(path: "Groves/Git/config")
	}

	public init(name: String = "", email: String = "") {
		self.name = name
		self.email = email
	}

	public var isValid: Bool {
		let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
		let emailComponents = email.split(separator: "@", omittingEmptySubsequences: false)
		return [name, self.email].allSatisfy {
			!$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				&& $0.rangeOfCharacter(from: .controlCharacters) == nil
				&& !$0.contains("<") && !$0.contains(">")
		} && email.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
			&& emailComponents.count == 2 && emailComponents.allSatisfy { !$0.isEmpty }
	}

	public func save(to url: URL = Self.defaultURL) throws {
		guard isValid else {
			throw NSError(
				domain: "Groves.GitIdentity",
				code: 1,
				userInfo: [
					NSLocalizedDescriptionKey: "Enter a name and valid email address without line breaks."
				]
			)
		}
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let content = """
			[user]
				name = "\(Self.escaped(name.trimmingCharacters(in: .whitespaces)))"
				email = "\(Self.escaped(email.trimmingCharacters(in: .whitespaces)))"
				useConfigOnly = true
			"""
		try content.write(to: url, atomically: true, encoding: .utf8)
	}

	private static func escaped(_ value: String) -> String {
		value.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
	}
}
