import Foundation

public struct RepositoryPullPreparation: Sendable {
	public let outcome: RepositoryPullOutcome
	public let snapshot: RepositorySnapshot

	public init(outcome: RepositoryPullOutcome, snapshot: RepositorySnapshot) {
		self.outcome = outcome
		self.snapshot = snapshot
	}
}
