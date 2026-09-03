import Foundation

public struct GitConflictHunk: Identifiable, Hashable, Sendable {
	public let index: Int
	public let base: String?
	public let current: String
	public let incoming: String

	public var id: Int { index }

	public init(index: Int, base: String?, current: String, incoming: String) {
		self.index = index
		self.base = base
		self.current = current
		self.incoming = incoming
	}
}
