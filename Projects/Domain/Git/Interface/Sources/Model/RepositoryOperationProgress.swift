public struct RepositoryOperationProgress: Hashable, Sendable {
	public let current: Int
	public let total: Int

	public init(current: Int, total: Int) {
		self.current = current
		self.total = total
	}
}
