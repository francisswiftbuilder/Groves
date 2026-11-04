import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct CommitPlanViewModelTests {
	private struct UseCase: RepositoryCommitPlanningUseCase {
		var load: @Sendable () async throws -> GitCommitPlan
		var reportsProgress = false
		var submit: @Sendable () async throws -> GitCommitPlanInput = { fatalError() }

		func loadPlan(at repositoryURL: URL) async throws -> GitCommitPlan { try await load() }
		func loadPlan(
			at repositoryURL: URL,
			progress: @escaping @Sendable (CommitAnalysisProgress) async -> Void
		) async throws -> GitCommitPlan {
			if reportsProgress { await progress(.init(phase: .analyzing, completed: 3, total: 10)) }
			return try await load()
		}
		func commit(_ task: GitCommitTask, from plan: GitCommitPlan, at repositoryURL: URL) async throws
			-> GitCommitPlanInput
		{
			try await submit()
		}
	}

	private actor Gate<Value: Sendable> {
		var count = 0
		var continuations: [Int: CheckedContinuation<Value, Error>] = [:]

		func wait() async throws -> Value {
			let id = count
			count += 1
			return try await withCheckedThrowingContinuation { continuations[id] = $0 }
		}

		func resume(_ id: Int, with value: Value) {
			continuations.removeValue(forKey: id)?.resume(returning: value)
		}
	}

	@Test
	func cancellationKeepsAnOlderGenerationFromReplacingTheCurrentRequest() async throws {
		let gate = Gate<GitCommitPlan>()
		let viewModel = makeViewModel(useCase: UseCase(load: { try await gate.wait() }))
		viewModel.didPresent()
		try await waitUntil { await gate.count == 1 }
		viewModel.onDisappear()
		viewModel.didPresent()
		try await waitUntil { await gate.count == 2 }
		await gate.resume(0, with: makePlan())
		try await Task.sleep(for: .milliseconds(30))
		#expect(viewModel.plan == nil)
		#expect(viewModel.isGenerating)
		let current = makePlan()
		await gate.resume(1, with: current)
		try await waitUntil { !viewModel.isGenerating }
		#expect(viewModel.tasks == current.tasks)
	}

	@Test
	func repeatedSubmissionCreatesOneCommitAndKeepsTheNextTask() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let viewModel = makeViewModel(
			useCase: UseCase(
				load: { plan }, submit: { try await gate.wait() }))
		viewModel.didPresent()
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommit()
		viewModel.didRequestCommit()
		#expect(viewModel.isCommitting)
		try await waitUntil { await gate.count == 1 }
		let remaining = GitCommitPlanInput(
			headHash: "new-head", indexFingerprint: "index", units: [plan.input.units[1]])
		await gate.resume(0, with: remaining)
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks == [plan.tasks[1]])
		#expect(viewModel.canCommit)
		#expect(await gate.count == 1)
	}

	@Test
	func movingAChangePreservesEachBlockExactlyOnce() async throws {
		let plan = makePlan()
		let viewModel = makeViewModel(useCase: UseCase(load: { plan }))
		viewModel.didPresent()
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didMoveSelectedUnit(to: plan.tasks[1].id)
		#expect(viewModel.plan?.isValid == true)
		#expect(viewModel.tasks.count == 1)
		#expect(Set(viewModel.tasks.flatMap(\.unitIDs)) == Set(plan.input.units.map(\.id)))
	}

	@Test
	func analysisProgressIsDeliveredAndClearedOnDismissal() async throws {
		let plan = makePlan()
		let viewModel = makeViewModel(useCase: UseCase(load: { plan }, reportsProgress: true))
		viewModel.didPresent()
		try await waitUntil { !viewModel.isGenerating }
		#expect(viewModel.analysisProgress?.completed == 3)
		#expect(viewModel.analysisProgress?.total == 10)
		viewModel.onDisappear()
		#expect(viewModel.analysisProgress == nil)
	}

	@Test
	func aFailedCommitKeepsTheEditedMessageForRetry() async throws {
		let plan = makePlan()
		let viewModel = makeViewModel(
			useCase: UseCase(
				load: { plan }, submit: { throw GitRepositoryError.commandFailed("Hook rejected commit") }))
		viewModel.didPresent()
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didUpdateSubject("fix: reviewed summary")
		viewModel.didRequestCommit()
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.selectedTask?.subject == "fix: reviewed summary")
		#expect(viewModel.errorMessage?.contains("Hook rejected commit") == true)
		#expect(viewModel.canCommit)
		#expect(viewModel.completedCount == 0)
	}

	private func makeViewModel(useCase: UseCase) -> CommitPlanViewModel {
		let snapshot = snapshot()
		let viewModel = CommitPlanViewModel(
			dependencies: .init(
				useCase: useCase,
				contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				repositoryURL: { URL(fileURLWithPath: "/tmp/GrovesCommitPlanTests") }),
			didProduceSnapshot: { _ in })
		viewModel.apply(snapshot)
		return viewModel
	}

	private func makePlan() -> GitCommitPlan {
		let units = ["first", "second"].map {
			GitCommitUnit(id: $0, path: "same.swift", patch: "+\($0)", hunk: nil)
		}
		return GitCommitPlan(
			input: .init(headHash: "head", indexFingerprint: "index", units: units),
			tasks: units.map { GitCommitTask(subject: "feat: \($0.id)", body: "", unitIDs: [$0.id]) },
			model: .onDevice)
	}

	private func snapshot() -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [
				.init(
					path: "same.swift", previousPath: nil, indexState: .modified, workingTreeState: .unchanged
				)
			],
			amendChanges: [], commits: [], branches: [], remotes: [], operationState: .normal,
			tags: [], stashes: [], fileTree: [])
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while await !condition() {
			guard clock.now < deadline else { throw CancellationError() }
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
