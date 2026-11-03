import DomainGitInterface
import Foundation
import Testing

@testable import DataGit

struct FoundationModelCommitPlanGeneratorTests {
	private actor Calls {
		var cloud = 0
		var device = 0

		func recordCloud() { cloud += 1 }
		func recordDevice() { device += 1 }
	}

	@Test
	func availableCloudModelIsPreferred() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in
				await calls.recordCloud()
				return response()
			},
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		let plan = try await generator.generatePlan(for: input())
		#expect(plan.model == .privateCloudCompute)
		#expect(plan.isValid)
		#expect(await calls.cloud == 1)
		#expect(await calls.device == 0)
	}

	@Test(arguments: [false, true])
	func cloudUnavailabilityAndFailureFallBackOnDevice(fails: Bool) async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in
				await calls.recordCloud()
				if fails { throw URLError(.notConnectedToInternet) }
				return nil
			},
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		let plan = try await generator.generatePlan(for: input())
		#expect(plan.model == .onDevice)
		#expect(plan.isValid)
		#expect(await calls.cloud == 1)
		#expect(await calls.device == 1)
	}

	@Test
	func cancellationDoesNotStartFallback() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in throw CancellationError() },
			deviceGeneration: { _ in
				await calls.recordDevice()
				return response()
			})
		await #expect(throws: CancellationError.self) {
			try await generator.generatePlan(for: input())
		}
		#expect(await calls.device == 0)
	}

	@Test(arguments: [[0, 0], [], [1], [-1]])
	func invalidModelAssignmentsAreRejected(ids: [Int]) async throws {
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				GeneratedCommitPlan(commits: [
					.init(subject: "fix: update file", body: "", changeIDs: ids)
				])
			})
		await #expect(throws: GitCommitPlanError.self) {
			try await generator.generatePlan(for: input())
		}
	}

	@Test
	func coAuthorAttributionIsRejected() async throws {
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { _ in
				GeneratedCommitPlan(commits: [
					.init(subject: "fix: update file", body: "Co-Authored-By: Someone", changeIDs: [0])
				])
			})
		await #expect(throws: GitCommitPlanError.self) {
			try await generator.generatePlan(for: input())
		}
	}

	private func input() -> GitCommitPlanInput {
		GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index",
			units: [
				GitCommitUnit(id: "block", path: "file.swift", patch: "+updated", hunk: nil)
			])
	}

	@Test
	func invalidMultilineSubjectIsRetriedBeforePresentingThePlan() async throws {
		let calls = Calls()
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				await calls.recordDevice()
				if await calls.device == 1 {
					return GeneratedCommitPlan(commits: [
						.init(subject: "fix: update file\n\nDetails", body: "", changeIDs: [0])
					])
				}
				#expect(prompt.contains("single line"))
				return response()
			})
		#expect(try await generator.generatePlan(for: input()).isValid)
		#expect(await calls.device == 2)
	}

	@Test
	func repositoryHistoryReachesBothModelsWithoutAttribution() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: ["fix(auth): 로그인 상태 복원\n\n- 세션 복원 처리\nCo-Authored-By: Example"])
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { prompt in
				#expect(prompt.contains("fix(auth): 로그인 상태 복원"))
				#expect(!prompt.contains("Co-Authored-By"))
				return nil
			},
			deviceGeneration: { prompt in
				#expect(prompt.contains("fix(auth): 로그인 상태 복원"))
				#expect(prompt.contains("Output language: Korean (ko)"))
				#expect(prompt.contains("Subject format: type(scope): description"))
				#expect(prompt.contains("style reference only"))
				#expect(!prompt.contains("Co-Authored-By"))
				return GeneratedCommitPlan(commits: [
					.init(subject: "fix(auth): 세션 상태 갱신", body: "- 세션 갱신 처리", changeIDs: [0])
				])
			})
		let result = try await generator.generatePlan(for: input)
		#expect(result.isValid)
		#expect(result.tasks.first?.subject == "fix(auth): 세션 상태 갱신")
		#expect(result.input == input)
	}

	@Test
	func longCommitHistoryIsBoundedBeforePrompting() async throws {
		let input = GitCommitPlanInput(
			headHash: "head", indexFingerprint: "index", units: input().units,
			recentCommitMessages: Array(repeating: String(repeating: "변경 내용\n", count: 1_000), count: 8))
		let generator = FoundationModelCommitPlanGenerator(
			cloudGeneration: { _ in nil },
			deviceGeneration: { prompt in
				#expect(prompt.utf8.count < 2_000)
				return response()
			})
		#expect(try await generator.generatePlan(for: input).isValid)
	}

	private func response() -> GeneratedCommitPlan {
		GeneratedCommitPlan(commits: [.init(subject: "fix: update file", body: "", changeIDs: [0])])
	}
}
