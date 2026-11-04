import DomainGit
import DomainGitInterface
import Foundation
import Testing

struct CommitPlanningSnapshotTests {
	private actor Repository: GitCommitPlanningRepository {
		var input: GitCommitPlanInput
		private(set) var reads = 0

		init(input: GitCommitPlanInput) { self.input = input }
		func replace(_ input: GitCommitPlanInput) { self.input = input }
		func requestCommitPlanInput(at repositoryURL: URL) async throws -> GitCommitPlanInput {
			reads += 1
			return input
		}
		func requestCommitTask(
			_ task: GitCommitTask, expecting input: GitCommitPlanInput, at repositoryURL: URL
		) async throws {
			throw GitRepositoryError.invalidOutput
		}
	}

	private struct Generator: CommitPlanGenerating {
		let operation: @Sendable (GitCommitPlanInput) async throws -> GitCommitPlan
		func generatePlan(for input: GitCommitPlanInput) async throws -> GitCommitPlan {
			try await operation(input)
		}
	}

	@Test
	func unchangedInputIsValidatedBeforePresentingThePlan() async throws {
		let input = makeInput()
		let repository = Repository(input: input)
		let useCase = DefaultRepositoryCommitPlanningUseCase(
			repository: repository, generator: Generator { makePlan($0) })
		let plan = try await useCase.loadPlan(at: URL(fileURLWithPath: "/tmp/Repository"))
		#expect(plan.isValid)
		#expect(await repository.reads == 2)
	}

	@Test(arguments: [false, true])
	func changesDuringGenerationRejectTheStalePlan(changesHead: Bool) async throws {
		let input = makeInput()
		let repository = Repository(input: input)
		let useCase = DefaultRepositoryCommitPlanningUseCase(
			repository: repository,
			generator: Generator { captured in
				await repository.replace(
					.init(
						headHash: changesHead ? "new-head" : captured.headHash,
						indexFingerprint: changesHead ? captured.indexFingerprint : "new-index",
						units: captured.units))
				return makePlan(captured)
			})
		await #expect(throws: GitCommitPlanError.self) {
			try await useCase.loadPlan(at: URL(fileURLWithPath: "/tmp/Repository"))
		}
		#expect(await repository.reads == 2)
	}

	private func makeInput() -> GitCommitPlanInput {
		.init(
			headHash: "head", indexFingerprint: "index",
			units: [
				.init(id: "change", path: "file.swift", patch: "+change", hunk: nil)
			])
	}

	private func makePlan(_ input: GitCommitPlanInput) -> GitCommitPlan {
		.init(
			input: input, tasks: [.init(subject: "fix: update file", body: "", unitIDs: ["change"])],
			model: .onDevice)
	}
}
