import DomainGit
import DomainGitInterface
import Foundation
import Testing

struct CommitPlanningSnapshotTests {
	private actor Repository: GitCommitPlanningRepository {
		var input: GitCommitPlanInput
		private(set) var reads = 0
		private(set) var commits = 0
		private let acceptsCommit: Bool

		init(input: GitCommitPlanInput, acceptsCommit: Bool = false) {
			self.input = input
			self.acceptsCommit = acceptsCommit
		}
		func replace(_ input: GitCommitPlanInput) { self.input = input }
		func requestCommitPlanInput(at repositoryURL: URL) async throws -> GitCommitPlanInput {
			reads += 1
			if commits > 0 { throw GitRepositoryError.invalidOutput }
			return input
		}
		func requestCommitTask(
			_ task: GitCommitTask, expecting input: GitCommitPlanInput, at repositoryURL: URL
		) async throws {
			guard acceptsCommit else { throw GitRepositoryError.invalidOutput }
			#expect(input == self.input)
			commits += 1
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

	@Test(arguments: [false, true])
	func refreshErrorIsReportedAsPostCommitOnlyWhenGitAcceptedTheCommit(acceptsCommit: Bool)
		async throws
	{
		let input = makeInput()
		let repository = Repository(input: input, acceptsCommit: acceptsCommit)
		let useCase = DefaultRepositoryCommitPlanningUseCase(
			repository: repository, generator: Generator { makePlan($0) })
		let plan = makePlan(input)
		let task = try #require(plan.tasks.first)
		let url = URL(fileURLWithPath: "/tmp/Repository")

		do {
			_ = try await useCase.commit(task, from: plan, at: url)
			Issue.record("Expected Git or refresh to fail")
		} catch GitCommitPlanError.committedButRefreshFailed(let reason) {
			#expect(acceptsCommit)
			#expect(reason == GitRepositoryError.invalidOutput.localizedDescription)
		} catch GitRepositoryError.invalidOutput {
			#expect(!acceptsCommit)
		}

		#expect(await repository.commits == (acceptsCommit ? 1 : 0))
		#expect(await repository.reads == (acceptsCommit ? 1 : 0))
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
