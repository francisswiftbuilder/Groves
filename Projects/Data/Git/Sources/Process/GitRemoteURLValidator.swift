import Foundation

enum GitRemoteURLValidator {
	private static let credentialQueryKeys: Set<String> = [
		"access_token",
		"private_token",
		"token",
		"oauth_token",
		"password",
	]

	static func containsEmbeddedCredential(_ remoteURL: String) -> Bool {
		guard let components = URLComponents(string: remoteURL) else {
			return false
		}
		if components.password?.isEmpty == false {
			return true
		}
		guard let queryItems = components.queryItems else { return false }
		return queryItems.contains { item in
			credentialQueryKeys.contains(item.name.lowercased()) && item.value?.isEmpty == false
		}
	}
}
