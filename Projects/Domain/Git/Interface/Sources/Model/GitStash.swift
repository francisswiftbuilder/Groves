import Foundation

public struct GitStash: Identifiable, Hashable, Sendable {
	public let reference: String
	public let hash: String
	public let subject: String
	public let date: Date?
	public let occurrence: Int

	public var id: String { "\(hash):\(subject):\(occurrence)" }

	public init(reference: String, hash: String, subject: String, date: Date?, occurrence: Int = 0) {
		self.reference = reference
		self.hash = hash
		self.subject = subject
		self.date = date
		self.occurrence = occurrence
	}
}
