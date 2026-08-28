import Foundation

enum GitRemoteURLValidator {
	private static let credentialQueryKeys: Set<String> = [
		"access_token",
		"private_token",
		"token",
		"oauth_token",
		"password",
	]

	private static let webSchemes: Set<String> = ["http", "https"]

	private static let schemeSeparator = "://"

	static func containsEmbeddedCredential(_ remoteURL: String) -> Bool {
		let remoteURL = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
		if containsCredentialQueryItem(remoteURL) {
			return true
		}
		guard let separator = remoteURL.range(of: schemeSeparator) else {
			return secureShellPathContainsPassword(remoteURL)
		}
		let scheme = remoteURL[remoteURL.startIndex..<separator.lowerBound].lowercased()
		let authority = remoteURL[separator.upperBound...].prefix { character in
			character != "/" && character != "?" && character != "#"
		}
		guard let userInfoEnd = authority.lastIndex(of: "@") else {
			return false
		}
		if webSchemes.contains(scheme) {
			return true
		}
		return authority[authority.startIndex..<userInfoEnd].contains(":")
	}

	private static func secureShellPathContainsPassword(_ remoteURL: String) -> Bool {
		guard let userInfoEnd = remoteURL.firstIndex(of: "@") else { return false }
		let userInfo = remoteURL[remoteURL.startIndex..<userInfoEnd]
		guard userInfo.contains("/") == false else { return false }
		return userInfo.contains(":")
	}

	private static func containsCredentialQueryItem(_ remoteURL: String) -> Bool {
		guard let queryStart = remoteURL.firstIndex(of: "?") else { return false }
		let query = remoteURL[remoteURL.index(after: queryStart)...].prefix { $0 != "#" }
		return query.split(separator: "&").contains { field in
			let pair = field.split(separator: "=", maxSplits: 1)
			guard pair.count == 2, let name = pair.first, pair[1].isEmpty == false else {
				return false
			}
			let rawName = String(name)
			guard let decodedName = rawName.removingPercentEncoding else {
				return rawName.contains("%")
			}
			return credentialQueryKeys.contains(decodedName.lowercased())
		}
	}
}
