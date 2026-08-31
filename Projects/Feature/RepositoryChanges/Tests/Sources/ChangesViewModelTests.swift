import DomainGitInterface
import XCTest

@testable import FeatureRepositoryChanges

@MainActor
final class ChangesViewModelTests: XCTestCase {
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

		XCTAssertEqual(viewModel.selectedChangeIDs, [.conflict(conflict.path)])
		XCTAssertEqual(selectedConflict, conflict)
		XCTAssertNil(selectedDiff)
	}

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
		XCTAssertEqual(selectedDiff?.source, .unstaged)
		XCTAssertEqual(selectedDiff?.workingTreeChange, change)

		await viewModel.didSelectChanges([.staged(change.id)])
		XCTAssertEqual(selectedDiff?.source, .staged)
		XCTAssertEqual(selectedDiff?.workingTreeChange, change)
	}

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

		XCTAssertTrue(viewModel.selectedChangeIDs.isEmpty)
		XCTAssertTrue(viewModel.changes.isEmpty)
		XCTAssertNil(selectedConflict)
		XCTAssertNil(selectedDiff)
	}

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

		XCTAssertEqual(viewModel.conflicts, [conflict])
	}

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

		XCTAssertTrue(reloadRequests.isEmpty)
	}

	private func makeViewModel(
		didSelectConflict: @escaping @MainActor (GitConflict?) -> Void = { _ in },
		didSelectDiff: @escaping @MainActor (ChangesDiffSelection?) -> Void = { _ in },
		didSelectDiffWithReload: @escaping @MainActor (ChangesDiffSelection?, Bool) -> Void = {
			_, _ in
		}
	) -> ChangesViewModel {
		ChangesViewModel(
			dependencies: ChangesViewModelDependencies(
				contentUseCase: ChangesContentUseCaseStub(),
				changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: ChangesViewModelActions(
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
