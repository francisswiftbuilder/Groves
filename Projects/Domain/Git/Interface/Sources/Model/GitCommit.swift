import Foundation

public struct GitCommit: Identifiable, Hashable, Sendable {
	public let hash: String
	public let shortHash: String
	public let parentHashes: [String]
	public let author: String
	public let authorEmail: String
	public let date: Date
	public let committer: String
	public let committerEmail: String
	public let committedDate: Date
	public let references: [String]
	public let subject: String
	public let body: String

	public var id: String { hash }

	public init(
		hash: String,
		shortHash: String,
		parentHashes: [String],
		author: String,
		authorEmail: String = "",
		date: Date,
		committer: String? = nil,
		committerEmail: String = "",
		committedDate: Date? = nil,
		references: [String],
		subject: String,
		body: String
	) {
		self.hash = hash
		self.shortHash = shortHash
		self.parentHashes = parentHashes
		self.author = author
		self.authorEmail = authorEmail
		self.date = date
		self.committer = committer ?? author
		self.committerEmail = committerEmail
		self.committedDate = committedDate ?? date
		self.references = references
		self.subject = subject
		self.body = body
	}
}
