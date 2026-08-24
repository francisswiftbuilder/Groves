import Foundation

public struct GitRemoteBranch: Identifiable, Hashable, Sendable {
	public let name: String
	public let fullName: String
	public let remoteName: String
	public let shortHash: String
	public let hash: String

	public var id: String { fullName }

	public init(
		name: String,
		fullName: String,
		remoteName: String,
		shortHash: String,
		hash: String
	) {
		self.name = name
		self.fullName = fullName
		self.remoteName = remoteName
		self.shortHash = shortHash
		self.hash = hash
	}
}
