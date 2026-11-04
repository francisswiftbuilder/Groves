import Foundation

public protocol GitCommitPlanningRepository: Sendable {
	func requestCommitPlanInput(at repositoryURL: URL) async throws -> GitCommitPlanInput
	func requestCommitTask(
		_ task: GitCommitTask,
		expecting input: GitCommitPlanInput,
		at repositoryURL: URL
	) async throws
}
