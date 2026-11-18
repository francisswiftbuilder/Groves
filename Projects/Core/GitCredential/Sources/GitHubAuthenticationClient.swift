import Foundation

public struct GitHubAuthenticationClient: Sendable {
	private struct ErrorResponse: Decodable {
		let message: String
	}

	private let session: URLSession

	public init(session: URLSession = URLSession(configuration: .ephemeral)) {
		self.session = session
	}

	public func account(token: String) async throws -> GitHubAccount {
		let (data, _) = try await request(URL(string: "https://api.github.com/user")!, token: token)
		return try JSONDecoder().decode(GitHubAccount.self, from: data)
	}

	public func repositories(
		token: String, progress: @Sendable ([GitHubRepository]) async -> Void = { _ in }
	) async throws -> [GitHubRepository] {
		var repositories: [GitHubRepository] = []
		var seen: Set<GitHubRepository.ID> = []
		var page = 1
		while true {
			try Task.checkCancellation()
			var components = URLComponents(string: "https://api.github.com/user/repos")!
			components.queryItems = [
				URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
				URLQueryItem(name: "per_page", value: "100"),
				URLQueryItem(name: "page", value: String(page)),
			]
			let (data, response) = try await request(components.url!, token: token)
			let results = try JSONDecoder().decode([GitHubRepository].self, from: data)
			repositories.append(contentsOf: results.filter { seen.insert($0.id).inserted })
			let links = response.value(forHTTPHeaderField: "Link") ?? ""
			guard !results.isEmpty,
				links.split(separator: ",").contains(where: {
					$0.split(separator: ";").dropFirst().contains {
						$0.trimmingCharacters(in: .whitespaces) == #"rel="next""#
					}
				})
			else { return repositories }
			await progress(repositories)
			page += 1
		}
	}

	public func repositoryFiles(for repository: GitHubRepository, token: String) async throws
		-> [GitHubRepositoryFile]
	{
		let (data, response) = try await request(
			repositoryEndpoint(for: repository).appending(path: "contents"),
			token: token, allowsNotFound: true)
		guard response.statusCode != 404 else { return [] }
		return try JSONDecoder().decode([GitHubRepositoryFile].self, from: data).sorted {
			if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
	}

	public func repositoryReadme(for repository: GitHubRepository, token: String) async throws
		-> GitHubRepositoryReadme
	{
		let (data, response) = try await request(
			repositoryEndpoint(for: repository).appending(path: "readme"),
			token: token, accept: "application/vnd.github.raw+json", allowsNotFound: true)
		let limit = 128 * 1_024
		return GitHubRepositoryReadme(
			markdown: response.statusCode == 404
				? nil : String(decoding: data.prefix(limit), as: UTF8.self),
			isTruncated: response.statusCode == 200 && data.count > limit)
	}

	private func repositoryEndpoint(for repository: GitHubRepository) -> URL {
		URL(string: "https://api.github.com/repos")!
			.appending(path: repository.fullName, directoryHint: .isDirectory)
	}

	private func request(
		_ url: URL, token: String, accept: String = "application/vnd.github+json",
		allowsNotFound: Bool = false
	) async throws -> (Data, HTTPURLResponse) {
		let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
		guard !token.isEmpty, token.rangeOfCharacter(from: invalidCharacters) == nil else {
			throw GitHubAuthenticationError.invalidToken
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue(accept, forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		let (data, response) = try await session.data(for: request)
		try Task.checkCancellation()
		guard let response = response as? HTTPURLResponse else {
			throw GitHubAuthenticationError.unavailable
		}
		switch response.statusCode {
		case 200:
			return (data, response)
		case 404 where allowsNotFound:
			return (data, response)
		case 401:
			throw GitHubAuthenticationError.invalidToken
		case 429:
			throw GitHubAuthenticationError.rateLimited
		case 403:
			let message = try? JSONDecoder().decode(ErrorResponse.self, from: data).message
			if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
				|| response.value(forHTTPHeaderField: "Retry-After") != nil
				|| message?.localizedCaseInsensitiveContains("rate limit") == true
			{
				throw GitHubAuthenticationError.rateLimited
			}
			throw GitHubAuthenticationError.forbidden
		default:
			throw GitHubAuthenticationError.unavailable
		}
	}
}
