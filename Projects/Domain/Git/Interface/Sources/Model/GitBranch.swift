import Foundation

public struct GitBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let shortHash: String
	public let hash: String
	public let upstream: String?
	public let pushRemoteName: String?
	public let upstreamRemoteName: String?
	public let upstreamRemoteReference: String?
	public let customUpstreamHash: String?
	public let aheadCount: Int
	public let behindCount: Int
	public let isCurrent: Bool

	public var id: String { name }

	public func tracks(_ branch: GitRemoteBranch) -> Bool {
		guard let reference = branch.remoteReference else { return false }
		return upstreamRemoteName == branch.remoteName && upstreamRemoteReference == reference
	}

	public init(
		name: String,
		shortHash: String,
		hash: String? = nil,
		upstream: String?,
		aheadCount: Int = 0,
		behindCount: Int = 0,
		isCurrent: Bool,
		pushRemoteName: String? = nil,
		upstreamRemoteName: String? = nil,
		upstreamRemoteReference: String? = nil,
		customUpstreamHash: String? = nil
	) {
		self.name = name
		self.shortHash = shortHash
		self.hash = hash ?? shortHash
		self.upstream = upstream
		self.pushRemoteName = pushRemoteName
		self.upstreamRemoteName = upstreamRemoteName
		self.upstreamRemoteReference = upstreamRemoteReference
		self.customUpstreamHash = customUpstreamHash
		self.aheadCount = aheadCount
		self.behindCount = behindCount
		self.isCurrent = isCurrent
	}
}
