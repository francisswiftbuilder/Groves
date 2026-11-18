import Foundation

public struct GitHubRepositoryFile: Decodable, Identifiable, Sendable {
	public let name: String
	public let path: String
	public let type: String
	private let htmlURL: URL?

	enum CodingKeys: String, CodingKey {
		case name, path, type
		case htmlURL = "html_url"
	}

	public var id: String { path }
	public var isDirectory: Bool { type == "dir" }

	public var webURL: URL? {
		guard htmlURL?.scheme == "https", htmlURL?.host == "github.com" else { return nil }
		return htmlURL
	}
}
