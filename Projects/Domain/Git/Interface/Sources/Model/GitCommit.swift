import Foundation

public struct GitCommit: Identifiable, Hashable, Sendable {
	public let hash: String
	public let shortHash: String
	public let parentHashes: [String]
	public let author: String
	public let date: Date
	public let references: [String]
	public let subject: String
	public let body: String

	public var id: String { hash }

	public init(
		hash: String,
		shortHash: String,
		parentHashes: [String],
		author: String,
		date: Date,
		references: [String],
		subject: String,
		body: String
	) {
		self.hash = hash
		self.shortHash = shortHash
		self.parentHashes = parentHashes
		self.author = author
		self.date = date
		self.references = references
		self.subject = subject
		self.body = body
	}
}
