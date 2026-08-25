import Foundation

public struct GitConflictContent: Hashable, Sendable {
	public let base: String?
	public let current: String?
	public let incoming: String?
	public let workingTree: String?
	public let hunks: [GitConflictHunk]
	public let baseData: Data?
	public let currentData: Data?
	public let incomingData: Data?
	public let workingTreeData: Data?

	public init(
		base: String?,
		current: String?,
		incoming: String?,
		workingTree: String?,
		hunks: [GitConflictHunk],
		baseData: Data? = nil,
		currentData: Data? = nil,
		incomingData: Data? = nil,
		workingTreeData: Data? = nil
	) {
		self.base = base
		self.current = current
		self.incoming = incoming
		self.workingTree = workingTree
		self.hunks = hunks
		self.baseData = baseData
		self.currentData = currentData
		self.incomingData = incomingData
		self.workingTreeData = workingTreeData
	}

	public var hasConflictMarkers: Bool {
		!hunks.isEmpty
	}
}
