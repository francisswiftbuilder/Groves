import DomainGitInterface
import Foundation

public struct DefaultRepositoryCommitPlanningUseCase: RepositoryCommitPlanningUseCase {
	private let repository: any GitCommitPlanningRepository
	private let generator: any CommitPlanGenerating

	public init(repository: any GitCommitPlanningRepository, generator: any CommitPlanGenerating) {
		self.repository = repository
		self.generator = generator
	}

	public func loadPlan(at repositoryURL: URL) async throws -> GitCommitPlan {
		try await loadPlan(at: repositoryURL, progress: { _ in })
	}

	public func loadPlan(
		at repositoryURL: URL,
		progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
	) async throws -> GitCommitPlan {
		let input = try await repository.requestCommitPlanInput(at: repositoryURL)
		guard !input.units.isEmpty else { throw GitCommitPlanError.noStagedChanges }
		let plan = try await generator.generatePlan(for: input, progress: progress)
		guard plan.input == input, plan.isValid else { throw GitCommitPlanError.invalidPlan }
		try Task.checkCancellation()
		guard try await repository.requestCommitPlanInput(at: repositoryURL) == input else {
			throw GitCommitPlanError.repositoryChanged
		}
		return plan
	}

	public func commit(
		_ task: GitCommitTask,
		from plan: GitCommitPlan,
		at repositoryURL: URL
	) async throws -> GitCommitPlanInput {
		guard plan.isValid, plan.tasks.contains(task) else { throw GitCommitPlanError.invalidPlan }
		try await repository.requestCommitTask(task, expecting: plan.input, at: repositoryURL)
		return try await repository.requestCommitPlanInput(at: repositoryURL)
	}
}
