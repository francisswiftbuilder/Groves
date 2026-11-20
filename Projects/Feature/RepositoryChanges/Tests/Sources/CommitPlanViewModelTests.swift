import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct CommitPlanViewModelTests {
	private struct UseCase: RepositoryCommitPlanningUseCase {
		var load: @Sendable () async throws -> GitCommitPlan
		var reportsProgress = false
		var submit: @Sendable (GitCommitTask, GitCommitPlan) async throws -> GitCommitPlanInput = {
			_, _ in
			fatalError()
		}

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
			try await submit(task, plan)
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

		func fail(_ id: Int, with error: any Error) {
			continuations.removeValue(forKey: id)?.resume(throwing: error)
		}
	}

	@Test
	func taskCommitParticipatesInTheParentMutationState() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let snapshot = snapshot()
		let parent = CommitViewModel(
			dependencies: .init(
				contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/repo") },
				commitPlanningUseCase: UseCase(load: { plan }, submit: { _, _ in try await gate.wait() })),
			actions: .init(
				didProduceSnapshot: { _ in }, didReceiveError: { _ in }, didChangeAmendingCommit: { _ in }))
		let model = try #require(parent.planningViewModel)
		defer { parent.onDisappear() }
		model.didRequestPlan()
		try await waitUntil { !model.isGenerating }
		#expect(!parent.isMutating)
		model.didRequestCommitAll()
		try await waitUntil { await gate.count == 1 }
		#expect(parent.isMutating)
		await gate.resume(0, with: remainingInput(in: plan, after: 1))
		try await waitUntil { await gate.count == 2 }
		#expect(parent.isMutating)
		await gate.resume(1, with: remainingInput(in: plan, after: 2))
		try await waitUntil { !model.isCommitting }
		#expect(!parent.isMutating)
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
				load: { plan }, submit: { _, _ in try await gate.wait() }))
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
	func commitAllUsesPlanOrderAndRefreshedInputWithoutDuplicateSubmissions() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let remaining = remainingInput(in: plan, after: 1)
		let viewModel = makeViewModel(
			useCase: UseCase(
				load: { plan },
				submit: { submitted, current in
					let index = await gate.count
					#expect(submitted == plan.tasks[index])
					#expect(current.input == (index == 0 ? plan.input : remaining))
					return try await gate.wait()
				}))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.selectedTaskID = plan.tasks.last?.id
		viewModel.didRequestCommitAll()
		viewModel.didRequestCommitAll()
		viewModel.didRequestCommit()
		try await waitUntil { await gate.count == 1 }
		#expect(viewModel.selectedTaskID == plan.tasks.first?.id)
		#expect(!viewModel.canCommitAll)
		await gate.resume(0, with: remaining)
		try await waitUntil { await gate.count == 2 }
		#expect(viewModel.isCommitting)
		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks == [plan.tasks[1]])
		#expect(viewModel.selectedTaskID == plan.tasks[1].id)
		await gate.resume(1, with: remainingInput(in: plan, after: 2))
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 2)
		#expect(viewModel.tasks.isEmpty)
		#expect(!viewModel.isPresented)
		#expect(viewModel.errorMessage == nil)
		#expect(await gate.count == 2)
	}

	@Test
	func failedBatchPreservesEditsAndRetriesOnlyTheRemainingCommits() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan(taskCount: 3)
		let viewModel = makeViewModel(
			useCase: UseCase(
				load: { plan },
				submit: { submitted, current in
					let attempt = await gate.count
					let index = [0, 1, 1, 2][attempt]
					#expect(submitted.id == plan.tasks[index].id)
					#expect(current.input.units == Array(plan.input.units.dropFirst(index)))
					if index == 1 { #expect(submitted.subject == "fix: reviewed summary") }
					return try await gate.wait()
				}))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.selectedTaskID = plan.tasks[1].id
		viewModel.didUpdateSubject("fix: reviewed summary")
		viewModel.didRequestCommitAll()
		try await waitUntil { await gate.count == 1 }
		await gate.resume(0, with: remainingInput(in: plan, after: 1))
		try await waitUntil { await gate.count == 2 }
		await gate.fail(1, with: GitRepositoryError.commandFailed("Hook rejected commit"))
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks.map(\.id) == Array(plan.tasks.dropFirst()).map(\.id))
		#expect(viewModel.selectedTask?.subject == "fix: reviewed summary")
		#expect(viewModel.errorMessage?.contains("Hook rejected commit") == true)
		#expect(viewModel.canCommitAll)
		#expect(await gate.count == 2)
		#expect(viewModel.isPresented)
		viewModel.didRequestCommitAll()
		try await waitUntil { await gate.count == 3 }
		await gate.resume(2, with: remainingInput(in: plan, after: 2))
		try await waitUntil { await gate.count == 4 }
		await gate.resume(3, with: remainingInput(in: plan, after: 3))
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 3)
		#expect(viewModel.tasks.isEmpty)
		#expect(viewModel.errorMessage == nil)
	}

	@Test(arguments: [false, true])
	func aCreatedCommitCannotBeRetriedAfterRefreshingFails(batch: Bool) async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let viewModel = makeViewModel(
			useCase: UseCase(
				load: { plan },
				submit: { submitted, _ in
					#expect(submitted.id == plan.tasks.first?.id)
					return try await gate.wait()
				}))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		if batch { viewModel.didRequestCommitAll() } else { viewModel.didRequestCommit() }
		try await waitUntil { await gate.count == 1 }

		let failure = GitCommitPlanError.committedButRefreshFailed("Index refresh unavailable")
		await gate.fail(0, with: failure)
		try await waitUntil { !viewModel.isCommitting }

		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks == Array(plan.tasks.dropFirst()))
		#expect(viewModel.selectedTaskID == plan.tasks.last?.id)
		#expect(viewModel.needsRefresh)
		#expect(viewModel.isPresented)
		#expect(viewModel.errorMessage == failure.localizedDescription)
		#expect(!viewModel.canCommitAll)
		#expect(!viewModel.canCommit)
		viewModel.didRequestCommit()
		viewModel.didRequestCommitAll()
		#expect(!viewModel.isCommitting)
		#expect(await gate.count == 1)
	}

	@Test
	func finalWorkspaceRefreshFailurePreservesTheCompletedBatch() async throws {
		let plan = makePlan()
		let commits = Gate<GitCommitPlanInput>()
		let initial = snapshot()
		let viewModel = CommitPlanViewModel(
			dependencies: .init(
				useCase: UseCase(load: { plan }, submit: { _, _ in try await commits.wait() }),
				contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in
					throw GitRepositoryError.commandFailed("Workspace unavailable")
				}),
				repositoryURL: { URL(fileURLWithPath: "/repo") }),
			didProduceSnapshot: { _ in Issue.record("Unexpected workspace snapshot") })
		viewModel.apply(initial)
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommitAll()
		try await waitUntil { await commits.count == 1 }
		await commits.resume(0, with: remainingInput(in: plan, after: 1))
		try await waitUntil { await commits.count == 2 }
		await commits.resume(1, with: remainingInput(in: plan, after: 2))
		try await waitUntil { !viewModel.isCommitting }

		#expect(viewModel.completedCount == 2)
		#expect(viewModel.tasks.isEmpty)
		#expect(viewModel.needsRefresh)
		#expect(
			viewModel.errorMessage
				== GitCommitPlanError.committedButRefreshFailed("Workspace unavailable")
				.localizedDescription)
		#expect(!viewModel.canCommitAll)
		#expect(await commits.count == 2)
	}

	@Test
	func changedRepositoryStopsTheBatchBeforeTheNextCommit() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let viewModel = makeViewModel(
			useCase: UseCase(load: { plan }, submit: { _, _ in try await gate.wait() }))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommitAll()
		try await waitUntil { await gate.count == 1 }
		await gate.resume(0, with: plan.input)
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks == [plan.tasks[1]])
		#expect(viewModel.needsRefresh)
		#expect(!viewModel.canCommitAll)
		#expect(viewModel.errorMessage == GitCommitPlanError.repositoryChanged.localizedDescription)
		viewModel.didRequestCommitAll()
		#expect(!viewModel.isCommitting)
		#expect(await gate.count == 1)
	}

	@Test
	func unexpectedStagedChangesAfterTheLastCommitRequireAnotherReview() async throws {
		let plan = makePlan(taskCount: 1)
		let viewModel = makeViewModel(
			useCase: UseCase(load: { plan }, submit: { _, _ in plan.input }))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommitAll()
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 1)
		#expect(viewModel.tasks.isEmpty)
		#expect(viewModel.needsRefresh)
		#expect(viewModel.errorMessage == GitCommitPlanError.repositoryChanged.localizedDescription)
	}

	@Test
	func batchAvailabilityDoesNotDependOnSelectionAndRejectsInvalidMessages() async throws {
		let plan = makePlan()
		let viewModel = makeViewModel(useCase: UseCase(load: { plan }))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.selectedTaskID = nil
		#expect(viewModel.canCommitAll)
		#expect(!viewModel.canCommit)
		viewModel.selectedTaskID = plan.tasks[1].id
		viewModel.didUpdateSubject("")
		#expect(!viewModel.canCommitAll)
		viewModel.didRequestCommitAll()
		#expect(!viewModel.isCommitting)
		#expect(viewModel.completedCount == 0)
	}

	@Test
	func cancelledBatchCannotContinueOrReplaceANewReview() async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		let viewModel = makeViewModel(
			useCase: UseCase(load: { plan }, submit: { _, _ in try await gate.wait() }))
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommitAll()
		try await waitUntil { await gate.count == 1 }
		viewModel.onDisappear()
		viewModel.didPresent()
		try await waitUntil { !viewModel.isGenerating }
		await gate.resume(0, with: remainingInput(in: plan, after: 1))
		try await Task.sleep(for: .milliseconds(30))
		#expect(!viewModel.isCommitting)
		#expect(viewModel.completedCount == 0)
		#expect(viewModel.tasks == plan.tasks)
		#expect(await gate.count == 1)
	}

	@Test(arguments: [false, true])
	func switchingRepositoriesStopsTheBatch(beforeStarting: Bool) async throws {
		let gate = Gate<GitCommitPlanInput>()
		let plan = makePlan()
		var repositoryURL = URL(fileURLWithPath: "/repo")
		let viewModel = makeViewModel(
			useCase: UseCase(load: { plan }, submit: { _, _ in try await gate.wait() }),
			repositoryURL: { repositoryURL })
		viewModel.didPresent()
		defer { viewModel.onDisappear() }
		try await waitUntil { !viewModel.isGenerating }
		viewModel.didRequestCommitAll()
		if !beforeStarting { try await waitUntil { await gate.count == 1 } }
		repositoryURL = URL(fileURLWithPath: "/other-repo")
		if !beforeStarting { await gate.resume(0, with: remainingInput(in: plan, after: 1)) }
		try await waitUntil { !viewModel.isCommitting }
		#expect(viewModel.completedCount == 0)
		#expect(viewModel.tasks == plan.tasks)
		#expect(await gate.count == (beforeStarting ? 0 : 1))
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
				load: { plan },
				submit: { _, _ in
					throw GitRepositoryError.commandFailed("Hook rejected commit")
				}))
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

	private func makeViewModel(
		useCase: UseCase,
		repositoryURL: @escaping @MainActor () -> URL? = {
			URL(fileURLWithPath: "/tmp/PluminonCommitPlanTests")
		}
	) -> CommitPlanViewModel {
		let snapshot = snapshot()
		let viewModel = CommitPlanViewModel(
			dependencies: .init(
				useCase: useCase,
				contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in snapshot }),
				repositoryURL: repositoryURL),
			didProduceSnapshot: { _ in })
		viewModel.apply(snapshot)
		return viewModel
	}

	private func makePlan(taskCount: Int = 2) -> GitCommitPlan {
		let units = ["first", "second", "third"].prefix(taskCount).map {
			GitCommitUnit(id: $0, path: "same.swift", patch: "+\($0)", hunk: nil)
		}
		return GitCommitPlan(
			input: .init(headHash: "head", indexFingerprint: "index", units: units),
			tasks: units.map { GitCommitTask(subject: "feat: \($0.id)", body: "", unitIDs: [$0.id]) },
			model: .onDevice)
	}

	private func remainingInput(in plan: GitCommitPlan, after count: Int) -> GitCommitPlanInput {
		GitCommitPlanInput(
			headHash: "head-\(count)", indexFingerprint: "index-\(count)",
			units: Array(plan.input.units.dropFirst(count)))
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
