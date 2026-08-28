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

	private func makeViewModel(
		didSelectConflict: @escaping @MainActor (GitConflict?) -> Void = { _ in },
		didSelectDiff: @escaping @MainActor (ChangesDiffSelection?) -> Void = { _ in }
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
				didSelectDiff: { selection, _ in didSelectDiff(selection) }
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
