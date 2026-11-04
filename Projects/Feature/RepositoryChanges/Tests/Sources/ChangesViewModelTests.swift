import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct ChangesViewModelTests {
	private actor SnapshotGate {
		private(set) var requestCount = 0
		private var continuations: [Int: CheckedContinuation<RepositorySnapshot, Error>] = [:]

		func load() async throws -> RepositorySnapshot {
			let index = requestCount
			requestCount += 1
			return try await withCheckedThrowingContinuation { continuations[index] = $0 }
		}

		func resume(_ index: Int, returning snapshot: RepositorySnapshot) {
			continuations.removeValue(forKey: index)?.resume(returning: snapshot)
		}
	}

	@Test
	func stagingImmediatelyBlocksRepeatedAndOpposingRequests() async throws {
		let gate = SnapshotGate()
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(
				stageOperation: { _, _ in try await gate.load() },
				unstageOperation: { _, _ in try await gate.load() }))
		defer { viewModel.onDisappear() }
		let change = WorkingTreeChange(
			path: "Sources/App.swift", previousPath: nil, indexState: .modified,
			workingTreeState: .modified)
		viewModel.apply(makeSnapshot(changes: [change]))
		viewModel.didRequestStage([change])
		#expect(viewModel.isLoading)
		viewModel.didRequestStage([change])
		viewModel.didRequestUnstage([change])
		for _ in 0..<100 {
			if await gate.requestCount > 0 { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		try await Task.sleep(for: .milliseconds(20))
		let count = await gate.requestCount
		#expect(count == 1)
		for index in 0..<count {
			await gate.resume(index, returning: makeSnapshot(changes: [change]))
		}
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(!viewModel.isLoading)
	}

	@Test
	func mixedSelectionMovesOnlyTheRequestedGroupAndKeepsTheSelectedFiles() async throws {
		let target = WorkingTreeChange(
			path: "Target.swift", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		let other = WorkingTreeChange(
			path: "Other.swift", previousPath: nil, indexState: .modified, workingTreeState: .modified)
		let stagedTarget = WorkingTreeChange(
			path: target.path, previousPath: nil, indexState: .modified, workingTreeState: .unchanged)
		let stagedSnapshot = makeSnapshot(changes: [other, stagedTarget])
		let unstagedTarget = target
		let unstagedSnapshot = makeSnapshot(changes: [other, unstagedTarget])
		weak var observedViewModel: ChangesViewModel?
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(
				stageOperation: { changes, _ in
					#expect(changes.map(\.path) == [target.path])
					return stagedSnapshot
				},
				unstageOperation: { changes, _ in
					#expect(changes.map(\.path) == [target.path])
					return unstagedSnapshot
				}),
			didProduceSnapshot: { observedViewModel?.apply($0) })
		observedViewModel = viewModel
		defer { viewModel.onDisappear() }
		viewModel.apply(makeSnapshot(changes: [other, target]))
		await viewModel.didSelectChanges([.staged(other.id), .unstaged(target.id)])
		#expect(viewModel.canStageSelection)
		#expect(viewModel.canUnstageSelection)
		viewModel.didRequestStageSelectedChanges()
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(viewModel.selectedChangeIDs == [.staged(other.id), .staged(target.id)])
		#expect(!viewModel.canStageSelection)
		await viewModel.didSelectChanges([.unstaged(other.id), .staged(target.id)])
		viewModel.didRequestUnstageSelectedChanges()
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(viewModel.selectedChangeIDs == [.unstaged(other.id), .unstaged(target.id)])
		#expect(!viewModel.canUnstageSelection)
	}

	@Test
	func stagingCompletionPreservesASelectionMadeWhileTheRequestWasRunning() async throws {
		let gate = SnapshotGate()
		let target = WorkingTreeChange(
			path: "Target.swift", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		let other = WorkingTreeChange(
			path: "Other.swift", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		weak var observedViewModel: ChangesViewModel?
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(stageOperation: { _, _ in try await gate.load() }),
			didProduceSnapshot: { observedViewModel?.apply($0) })
		observedViewModel = viewModel
		defer { viewModel.onDisappear() }
		viewModel.apply(makeSnapshot(changes: [target, other]))
		await viewModel.didSelectChanges([.unstaged(target.id)])
		viewModel.didRequestStageSelectedChanges()
		for _ in 0..<100 {
			if await gate.requestCount > 0 { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		await viewModel.didSelectChanges([.unstaged(other.id)])
		await gate.resume(
			0,
			returning: makeSnapshot(changes: [
				.init(
					path: target.path, previousPath: nil, indexState: .modified, workingTreeState: .unchanged),
				other,
			]))
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(viewModel.selectedChangeIDs == [.unstaged(other.id)])
	}

	@Test
	func amendStagingUsesTheIncludedChangesSection() async throws {
		let target = WorkingTreeChange(
			path: "Target.swift", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		let stagedSnapshot = makeSnapshot(
			changes: [
				.init(
					path: target.path, previousPath: nil, indexState: .modified, workingTreeState: .unchanged)
			],
			amendChanges: [.init(path: target.path, previousPath: nil, state: .modified)])
		let unstagedSnapshot = makeSnapshot(changes: [target])
		weak var observedViewModel: ChangesViewModel?
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(
				stageOperation: { _, _ in stagedSnapshot },
				unstageAmendOperation: { changes, _ in
					#expect(changes.map(\.path) == [target.path])
					return unstagedSnapshot
				}),
			didProduceSnapshot: { observedViewModel?.apply($0) })
		observedViewModel = viewModel
		defer { viewModel.onDisappear() }
		viewModel.apply(makeSnapshot(changes: [target]))
		viewModel.didSetAmendingCommit(true)
		viewModel.didRequestStageSelectedChanges()
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(viewModel.filteredStagedChanges.isEmpty)
		#expect(viewModel.selectedChangeIDs == [.amend(target.id)])
		#expect(viewModel.canUnstageSelection)
		viewModel.didRequestUnstageSelectedChanges()
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(viewModel.selectedChangeIDs == [.unstaged(target.id)])
		#expect(viewModel.filteredAmendChanges.isEmpty)
	}

	@Test
	func bulkStagingLeavesUnresolvedConflictsToTheConflictActions() async throws {
		let target = WorkingTreeChange(
			path: "Target.swift", previousPath: nil, indexState: .unchanged, workingTreeState: .modified)
		let conflict = GitConflict(
			path: "Conflict.swift", kind: .bothModified, hasBase: true, hasOurs: true, hasTheirs: true)
		let snapshot = makeSnapshot(
			changes: [
				target,
				.init(
					path: conflict.path, previousPath: nil, indexState: .unmerged, workingTreeState: .unmerged
				),
			],
			operationState: .init(head: .attached, conflicts: [conflict]))
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(stageOperation: { changes, _ in
				#expect(changes.map(\.path) == [target.path])
				return snapshot
			}))
		defer { viewModel.onDisappear() }
		viewModel.apply(snapshot)
		#expect(!viewModel.canStageSelection)
		#expect(viewModel.canStageAllChanges)
		await viewModel.didSelectChanges([.staged(conflict.path), .unstaged(conflict.path)])
		#expect(!viewModel.canStageSelection)
		#expect(!viewModel.canUnstageSelection)
		viewModel.didRequestStageAllChanges()
		for _ in 0..<100 {
			if !viewModel.isLoading { break }
			try await Task.sleep(for: .milliseconds(1))
		}
		#expect(!viewModel.isLoading)
	}

	@Test
	func testApplyingSnapshotSelectsConflictBeforeWorkingTreeChanges() {
		let conflict = GitConflict(
			path: "Sources/Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		let change = WorkingTreeChange(
			path: "Sources/App.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		var selectedConflict: GitConflict?
		var selectedDiff: ChangesDiffSelection?
		let viewModel = makeViewModel(
			didSelectConflict: { selectedConflict = $0 },
			didSelectDiff: { selectedDiff = $0 }
		)

		viewModel.apply(
			makeSnapshot(
				changes: [change],
				operationState: RepositoryOperationState(
					head: .attached,
					conflicts: [conflict]
				)
			)
		)

		#expect(viewModel.selectedChangeIDs == [.conflict(conflict.path)])
		#expect(selectedConflict == conflict)
		#expect(selectedDiff == nil)
	}

	@Test
	func testSelectingStagedAndUnstagedRowsProducesTheMatchingDiffSource() async {
		let change = WorkingTreeChange(
			path: "Sources/App.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		var selectedDiff: ChangesDiffSelection?
		let viewModel = makeViewModel(didSelectDiff: { selectedDiff = $0 })
		viewModel.apply(makeSnapshot(changes: [change]))

		await viewModel.didSelectChanges([.unstaged(change.id)])
		#expect(selectedDiff?.source == .unstaged)
		#expect(selectedDiff?.workingTreeChange == change)

		await viewModel.didSelectChanges([.staged(change.id)])
		#expect(selectedDiff?.source == .staged)
		#expect(selectedDiff?.workingTreeChange == change)
	}

	@Test
	func testResetClearsSelectionAndPresentationOutputs() {
		let change = WorkingTreeChange(
			path: "Sources/App.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)
		var selectedConflict: GitConflict? = GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		var selectedDiff: ChangesDiffSelection?
		let viewModel = makeViewModel(
			didSelectConflict: { selectedConflict = $0 },
			didSelectDiff: { selectedDiff = $0 }
		)
		viewModel.apply(makeSnapshot(changes: [change]))

		viewModel.reset()

		#expect(viewModel.selectedChangeIDs.isEmpty)
		#expect(viewModel.changes.isEmpty)
		#expect(selectedConflict == nil)
		#expect(selectedDiff == nil)
	}

	@Test
	func testApplyingConflictOnlySnapshotChangePublishesConflictState() {
		let change = WorkingTreeChange(
			path: "Sources/App.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let conflict = GitConflict(
			path: "Sources/Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		let viewModel = makeViewModel()
		viewModel.apply(makeSnapshot(changes: [change]))

		viewModel.apply(
			makeSnapshot(
				changes: [change],
				operationState: RepositoryOperationState(
					head: .attached,
					conflicts: [conflict]
				)
			)
		)

		#expect(viewModel.conflicts == [conflict])
	}

	@Test
	func testApplyingIdenticalSnapshotDoesNotReloadSelectedDiff() {
		let change = WorkingTreeChange(
			path: "Sources/App.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		var reloadRequests: [Bool] = []
		let viewModel = makeViewModel(
			didSelectDiffWithReload: { _, forceReload in
				reloadRequests.append(forceReload)
			}
		)
		let snapshot = makeSnapshot(changes: [change])
		viewModel.apply(snapshot)
		reloadRequests.removeAll()

		viewModel.apply(snapshot, revalidatesSelectedDiff: false)

		#expect(reloadRequests.isEmpty)
	}

	private func makeViewModel(
		changesUseCase: ChangesUseCaseStub = ChangesUseCaseStub(),
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in },
		didSelectConflict: @escaping @MainActor (GitConflict?) -> Void = { _ in },
		didSelectDiff: @escaping @MainActor (ChangesDiffSelection?) -> Void = { _ in },
		didSelectDiffWithReload: @escaping @MainActor (ChangesDiffSelection?, Bool) -> Void = {
			_, _ in
		}
	) -> ChangesViewModel {
		ChangesViewModel(
			dependencies: ChangesViewModel.Dependencies(
				contentUseCase: ChangesContentUseCaseStub(),
				changesUseCase: changesUseCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: ChangesViewModel.Actions(
				didProduceSnapshot: didProduceSnapshot,
				didReceiveError: { _ in },
				didSelectConflict: didSelectConflict,
				didSelectDiff: { selection, forceReload in
					didSelectDiff(selection)
					didSelectDiffWithReload(selection, forceReload)
				}
			)
		)
	}

	private func makeSnapshot(
		changes: [WorkingTreeChange],
		operationState: RepositoryOperationState = .normal,
		amendChanges: [GitAmendChange] = []
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: amendChanges,
			commits: [],
			branches: [],
			remotes: [],
			operationState: operationState,
			tags: [],
			stashes: [],
			fileTree: []
		)
	}
}
