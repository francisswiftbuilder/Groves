import Foundation

public protocol CommitPlanGenerating: Sendable {
	func generatePlan(for input: GitCommitPlanInput) async throws -> GitCommitPlan
	func generatePlan(
		for input: GitCommitPlanInput,
		progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
	) async throws -> GitCommitPlan
}

extension CommitPlanGenerating {
	public func generatePlan(
		for input: GitCommitPlanInput,
		progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
	) async throws -> GitCommitPlan {
		try await generatePlan(for: input)
	}
}
