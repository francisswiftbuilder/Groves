import Foundation

public struct CommitAnalysisProgress: Sendable {
	public enum Phase: Sendable {
		case analyzing
		case grouping
	}

	public let phase: Phase
	public let completed: Int
	public let total: Int

	public init(phase: Phase, completed: Int, total: Int) {
		self.phase = phase
		self.completed = completed
		self.total = total
	}
}
