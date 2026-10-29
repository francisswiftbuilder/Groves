import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct ChangesViewModelTests {
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
		didSelectConflict: @escaping @MainActor (GitConflict?) -> Void = { _ in },
		didSelectDiff: @escaping @MainActor (ChangesDiffSelection?) -> Void = { _ in },
		didSelectDiffWithReload: @escaping @MainActor (ChangesDiffSelection?, Bool) -> Void = {
			_, _ in
		}
	) -> ChangesViewModel {
		ChangesViewModel(
			dependencies: ChangesViewModel.Dependencies(
				contentUseCase: ChangesContentUseCaseStub(),
				changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: ChangesViewModel.Actions(
				didProduceSnapshot: { _ in },
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
		operationState: RepositoryOperationState = .normal
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: [],
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
