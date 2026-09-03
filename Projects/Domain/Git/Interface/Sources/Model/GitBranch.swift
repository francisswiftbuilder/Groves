import Foundation

public struct GitBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let upstream: String?
	public let aheadCount: Int
	public let behindCount: Int
	public let isCurrent: Bool

	public var id: String { name }

	public init(
		name: String,
		shortHash: String,
		upstream: String?,
		aheadCount: Int = 0,
		behindCount: Int = 0,
		isCurrent: Bool
	) {
		self.name = name
		self.shortHash = shortHash
		self.upstream = upstream
		self.aheadCount = aheadCount
		self.behindCount = behindCount
		self.isCurrent = isCurrent
	}
}
