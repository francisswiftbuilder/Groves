import Foundation

public struct GitHubRepository: Decodable, Hashable, Identifiable, Sendable {
	public let id: Int
	public let fullName: String
	public let description: String?
	public let defaultBranch: String?
	public let isPrivate: Bool
	public let isArchived: Bool

	enum CodingKeys: String, CodingKey {
		case id
		case fullName = "full_name"
		case description
		case defaultBranch = "default_branch"
		case isPrivate = "private"
		case isArchived = "archived"
	}

	public var webURL: URL {
		URL(string: "https://github.com")!.appending(path: fullName, directoryHint: .notDirectory)
	}

	public var cloneURL: URL {
		webURL.appendingPathExtension("git")
	}
}
