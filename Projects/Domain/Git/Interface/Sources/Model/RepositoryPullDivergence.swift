import Foundation

public struct RepositoryPullDivergence: Hashable, Sendable {
	public let upstream: String
	public let aheadCount: Int
	public let behindCount: Int

	public init(upstream: String, aheadCount: Int, behindCount: Int) {
		self.upstream = upstream
		self.aheadCount = aheadCount
		self.behindCount = behindCount
	}
}
