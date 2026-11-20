public struct RepositoryReferenceMutationResult: Sendable {
	public let snapshot: RepositorySnapshot?
	public let message: String?

	public init(snapshot: RepositorySnapshot?, message: String? = nil) {
		self.snapshot = snapshot
		self.message = message
	}
}
