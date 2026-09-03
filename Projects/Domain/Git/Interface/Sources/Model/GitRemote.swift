import Foundation

public struct GitRemote: Identifiable, Hashable, Sendable {
	public let name: String
	public let fetchURL: String?
	public let pushURL: String?
	public let branches: [GitRemoteBranch]

	public var id: String { name }

	public init(
		name: String,
		fetchURL: String?,
		pushURL: String?,
		branches: [GitRemoteBranch] = []
	) {
		self.name = name
		self.fetchURL = fetchURL
		self.pushURL = pushURL
		self.branches = branches
	}
}
