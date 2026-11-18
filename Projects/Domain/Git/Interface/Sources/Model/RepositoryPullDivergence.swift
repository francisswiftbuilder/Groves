import Foundation

public struct RepositoryPullDivergence: Hashable, Sendable {
	public let branchName: String
	public let headHash: String
	public let upstream: String
	public let upstreamHash: String
	public let aheadCount: Int
	public let behindCount: Int

	public init(
		branchName: String, headHash: String, upstream: String, upstreamHash: String,
		aheadCount: Int, behindCount: Int
	) {
		self.branchName = branchName
		self.headHash = headHash
		self.upstream = upstream
		self.upstreamHash = upstreamHash
		self.aheadCount = aheadCount
		self.behindCount = behindCount
	}
}
