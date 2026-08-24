import Foundation

public struct GitStash: Identifiable, Hashable, Sendable {
	public let reference: String
	public let hash: String
	public let subject: String
	public let date: Date?

	public var id: String { reference }

	public init(reference: String, hash: String, subject: String, date: Date?) {
		self.reference = reference
		self.hash = hash
		self.subject = subject
		self.date = date
	}
}
