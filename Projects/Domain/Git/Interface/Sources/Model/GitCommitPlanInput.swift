import Foundation

public struct GitCommitPlanInput: Equatable, Sendable {
	public let headHash: String?
	public let indexFingerprint: String
	public let units: [GitCommitUnit]
	public let recentCommitMessages: [String]

	public init(
		headHash: String?, indexFingerprint: String, units: [GitCommitUnit],
		recentCommitMessages: [String] = []
	) {
		self.headHash = headHash
		self.indexFingerprint = indexFingerprint
		self.units = units
		self.recentCommitMessages = recentCommitMessages
	}
}
