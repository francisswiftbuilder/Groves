import Foundation

public struct GitRemoteBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let fullName: String
	public let remoteName: String
	public let shortHash: String
	public let hash: String
	public let pushURLs: [String]
	public let remoteReference: String?

	public var id: String { fullName }
	public var remoteDisplayName: String {
		guard let remoteReference, remoteReference.hasPrefix("refs/heads/") else { return fullName }
		return "\(remoteName)/\(remoteReference.dropFirst("refs/heads/".count))"
	}

	public init(
		name: String,
		fullName: String,
		remoteName: String,
		shortHash: String,
		hash: String,
		pushURLs: [String] = [],
		remoteReference: String? = nil
	) {
		self.name = name
		self.fullName = fullName
		self.remoteName = remoteName
		self.shortHash = shortHash
		self.hash = hash
		self.pushURLs = pushURLs
		self.remoteReference = remoteReference
	}
}
