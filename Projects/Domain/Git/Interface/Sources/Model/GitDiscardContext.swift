public struct GitDiscardContext: Equatable, Sendable {
	public let changes: [WorkingTreeChange]
	public let fingerprint: [String]

	public init(changes: [WorkingTreeChange], fingerprint: [String]) {
		self.changes = changes
		self.fingerprint = fingerprint
	}
}
