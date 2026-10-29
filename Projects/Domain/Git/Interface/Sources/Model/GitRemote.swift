import Foundation

public struct GitRemote: Identifiable, Hashable, Sendable {
	public let name: String
	public let fetchURLs: [String]
	public let pushURLs: [String]
	public let branches: [GitRemoteBranch]

	public var id: String { name }
	public var fetchURL: String? { fetchURLs.first }
	public var pushURL: String? { pushURLs.first }
	public var hasMultipleURLs: Bool { fetchURLs.count > 1 || pushURLs.count > 1 }

	public init(
		name: String,
		fetchURL: String?,
		pushURL: String?,
		branches: [GitRemoteBranch] = []
	) {
		self.init(
			name: name,
			fetchURLs: fetchURL.map { [$0] } ?? [],
			pushURLs: pushURL.map { [$0] } ?? [],
			branches: branches
		)
	}

	public init(
		name: String, fetchURLs: [String], pushURLs: [String], branches: [GitRemoteBranch] = []
	) {
		self.name = name
		self.fetchURLs = fetchURLs
		self.pushURLs = pushURLs
		self.branches = branches
	}
}
