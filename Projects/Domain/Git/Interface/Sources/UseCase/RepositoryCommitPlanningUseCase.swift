import Foundation

public protocol RepositoryCommitPlanningUseCase: Sendable {
	func loadPlan(at repositoryURL: URL) async throws -> GitCommitPlan
	func loadPlan(
		at repositoryURL: URL,
		progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
	) async throws -> GitCommitPlan
	func commit(
		_ task: GitCommitTask,
		from plan: GitCommitPlan,
		at repositoryURL: URL
	) async throws -> GitCommitPlanInput
}

extension RepositoryCommitPlanningUseCase {
	public func loadPlan(
		at repositoryURL: URL,
		progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
	) async throws -> GitCommitPlan {
		try await loadPlan(at: repositoryURL)
	}
}
