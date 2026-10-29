public struct RepositoryStashMutationResult: Sendable {
	public let outcome: RepositoryStashOutcome
	public let snapshot: RepositorySnapshot

	public init(outcome: RepositoryStashOutcome, snapshot: RepositorySnapshot) {
		self.outcome = outcome
		self.snapshot = snapshot
	}
}
