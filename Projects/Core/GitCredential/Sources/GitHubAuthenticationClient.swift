import Foundation

public struct GitHubAuthenticationClient: Sendable {
	private let session: URLSession

	public init(session: URLSession = URLSession(configuration: .ephemeral)) {
		self.session = session
	}

	public func account(token: String) async throws -> GitHubAccount {
		let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
		guard !token.isEmpty, token.rangeOfCharacter(from: invalidCharacters) == nil else {
			throw GitHubAuthenticationError.invalidToken
		}
		var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
		request.timeoutInterval = 30
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		let (data, response) = try await session.data(for: request)
		try Task.checkCancellation()
		guard let response = response as? HTTPURLResponse else {
			throw GitHubAuthenticationError.unavailable
		}
		switch response.statusCode {
		case 200:
			return try JSONDecoder().decode(GitHubAccount.self, from: data)
		case 401:
			throw GitHubAuthenticationError.invalidToken
		case 403, 429:
			throw GitHubAuthenticationError.forbidden
		default:
			throw GitHubAuthenticationError.unavailable
		}
	}
}
