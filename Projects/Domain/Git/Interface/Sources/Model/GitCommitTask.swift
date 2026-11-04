import Foundation

public struct GitCommitTask: Identifiable, Equatable, Sendable {
	public let id: UUID
	public var subject: String
	public var body: String
	public var unitIDs: [String]

	public init(id: UUID = UUID(), subject: String, body: String, unitIDs: [String]) {
		self.id = id
		self.subject = subject
		self.body = body
		self.unitIDs = unitIDs
	}

	public var hasValidMessage: Bool {
		let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
		return !subject.isEmpty && !subject.contains(where: \.isNewline)
			&& !(subject + "\n" + body).localizedCaseInsensitiveContains("co-authored-by:")
	}
}
