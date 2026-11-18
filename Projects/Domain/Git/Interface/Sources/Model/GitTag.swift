import Foundation

public struct GitTag: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let targetHash: String
	public let objectHash: String
	public let date: Date?
	public let subject: String

	public var id: String { name }

	public init(
		name: String,
		shortHash: String,
		targetHash: String,
		date: Date?,
		subject: String,
		objectHash: String? = nil
	) {
		self.name = name
		self.shortHash = shortHash
		self.targetHash = targetHash
		self.objectHash = objectHash ?? targetHash
		self.date = date
		self.subject = subject
	}
}
