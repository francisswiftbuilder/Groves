public struct RepositoryOperation: Hashable, Sendable {
	public let kind: RepositoryOperationKind
	public let progress: RepositoryOperationProgress?

	public init(kind: RepositoryOperationKind, progress: RepositoryOperationProgress? = nil) {
		self.kind = kind
		self.progress = progress
	}
}
