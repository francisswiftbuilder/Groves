public struct GitResetContext: Hashable, Sendable {
	public let branchName: String
	public let headHash: String

	public init(branchName: String, headHash: String) {
		self.branchName = branchName
		self.headHash = headHash
	}
}
