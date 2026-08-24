import Foundation

public struct GitBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let upstream: String?
	public let isCurrent: Bool

	public var id: String { name }

	public init(name: String, shortHash: String, upstream: String?, isCurrent: Bool) {
		self.name = name
		self.shortHash = shortHash
		self.upstream = upstream
		self.isCurrent = isCurrent
	}
}
