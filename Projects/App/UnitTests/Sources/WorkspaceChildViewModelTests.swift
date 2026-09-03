import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryHistory
@testable import FeatureRepositoryStashes
@testable import Groves

@MainActor
final class WorkspaceChildViewModelTests: XCTestCase {
	func testRepositoryWorkspaceOwnsChildViewModelLifetime() {
		var workspace: RepositoryWorkspace? = makeRepositoryWorkspace()
		let viewModel = workspace?.viewModel
		weak let changesViewModel = workspace?.changesViewModel
		weak let changesDiffViewModel = workspace?.changesDiffViewModel
		weak let commitViewModel = workspace?.commitViewModel
		weak let conflictViewModel = workspace?.conflictViewModel
		weak let historyViewModel = workspace?.historyViewModel
		weak let operationViewModel = workspace?.operationViewModel
		weak let referencesViewModel = workspace?.referencesViewModel
		weak let syncViewModel = workspace?.syncViewModel
		weak let remotesViewModel = workspace?.remotesViewModel
		weak let stashesViewModel = workspace?.stashesViewModel
		weak let treeViewModel = workspace?.treeViewModel
		weak let diffPreferences = workspace?.diffPreferences
		weak let focusedActionsViewModel = workspace?.focusedActionsViewModel

		workspace = nil

		XCTAssertNotNil(viewModel)
		XCTAssertNil(changesViewModel)
		XCTAssertNil(changesDiffViewModel)
		XCTAssertNil(commitViewModel)
		XCTAssertNil(conflictViewModel)
		XCTAssertNil(historyViewModel)
		XCTAssertNil(operationViewModel)
		XCTAssertNil(referencesViewModel)
		XCTAssertNil(syncViewModel)
		XCTAssertNil(remotesViewModel)
		XCTAssertNil(stashesViewModel)
		XCTAssertNil(treeViewModel)
		XCTAssertNil(diffPreferences)
		XCTAssertNil(focusedActionsViewModel)
	}

	func testSnapshotIsDistributedAcrossChildViewModels() async throws {
		let workspace = makeRepositoryWorkspace()
		let preferences = workspace.diffPreferences
		let changesViewModel = workspace.changesViewModel
		let changesDiffViewModel = workspace.changesDiffViewModel
		let historyViewModel = workspace.historyViewModel
		let referencesViewModel = workspace.referencesViewModel
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)
		let commit = GitCommit(
			hash: "abcdef123456",
			shortHash: "abcdef1",
			parentHashes: [],
			author: "Groves",
			date: .distantPast,
			references: ["HEAD"],
			subject: "Initial",
			body: ""
		)
		let branch = GitBranch(
			name: "develop",
			shortHash: "abcdef1",
			upstream: nil,
			isCurrent: true
		)
		let snapshot = RepositorySnapshot(
			changes: [change],
			amendChanges: [],
			commits: [commit],
			branches: [branch],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)

		workspace.viewModel.didProduceSnapshot(snapshot)
		try await waitUntil { historyViewModel.commitGraphItems.isEmpty == false }

		XCTAssertEqual(changesViewModel.changes, [change])
		XCTAssertEqual(historyViewModel.commitGraphItems.map(\.commit), [commit])
		XCTAssertEqual(referencesViewModel.branches, [branch])
		XCTAssertTrue(changesDiffViewModel.preferences === preferences)
	}

	func testWorkspaceDisappearCancelsPendingDebouncedSearch() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = [
			GitCommit(
				hash: "111111111111",
				shortHash: "1111111",
				parentHashes: [],
				author: "Groves",
				date: .distantPast,
				references: ["HEAD"],
				subject: "First",
				body: ""
			),
			GitCommit(
				hash: "222222222222",
				shortHash: "2222222",
				parentHashes: [],
				author: "Groves",
				date: .distantPast,
				references: [],
				subject: "Second",
				body: ""
			),
		]
		let snapshot = RepositorySnapshot(
			changes: [],
			amendChanges: [],
			commits: commits,
			branches: [],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)

		workspace.viewModel.didProduceSnapshot(snapshot)
		try await waitUntil { historyViewModel.commitGraphItems.count == commits.count }

		historyViewModel.didChangeSearchText("missing")
		workspace.onDisappear()
		try await Task.sleep(for: .milliseconds(200))

		XCTAssertEqual(historyViewModel.displayedCommitGraphItems.count, commits.count)
	}

	func testWorkspaceAppearResumesIncompleteHistoryLayout() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = (0..<1_000).reversed().map { index in
			GitCommit(
				hash: String(format: "%040d", index),
				shortHash: String(format: "%07d", index),
				parentHashes: index == 0 ? [] : [String(format: "%040d", index - 1)],
				author: "Groves",
				date: .distantPast,
				references: index == 999 ? ["HEAD"] : [],
				subject: "Commit \(index)",
				body: ""
			)
		}

		workspace.viewModel.didProduceSnapshot(
			RepositorySnapshot(
				changes: [],
				amendChanges: [],
				commits: commits,
				branches: [],
				remotes: [],
				operationState: .normal,
				tags: [],
				stashes: [],
				fileTree: []
			)
		)
		workspace.onDisappear()
		workspace.onAppear()

		try await waitUntil { historyViewModel.commitGraphItems.count == commits.count }

		XCTAssertEqual(historyViewModel.commitGraphItems.map(\.commit), commits)
	}

	func testStashesViewModelTracksWorkingTreeStateWithoutTheChangesViewModel() {
		let workspace = makeRepositoryWorkspace()
		let stashesViewModel = workspace.stashesViewModel
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .unchanged
		)

		XCTAssertFalse(stashesViewModel.hasChanges)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [change]))

		XCTAssertTrue(stashesViewModel.hasChanges)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: []))

		XCTAssertFalse(stashesViewModel.hasChanges)

		stashesViewModel.didChangeWorkingTreeState(hasChanges: true)

		XCTAssertTrue(stashesViewModel.hasChanges)

		stashesViewModel.reset()

		XCTAssertFalse(stashesViewModel.hasChanges)
	}

	func testFocusedActionsFollowLifecycleAndSelectionState() async {
		let workspace = makeRepositoryWorkspace()
		let branch = GitBranch(
			name: "feature",
			shortHash: "abcdef1",
			upstream: nil,
			isCurrent: false
		)
		workspace.viewModel.didProduceSnapshot(
			RepositorySnapshot(
				changes: [],
				amendChanges: [],
				commits: [],
				branches: [branch],
				remotes: [],
				operationState: .normal,
				tags: [],
				stashes: [],
				fileTree: []
			)
		)
		workspace.referencesViewModel.selectedBranchID = branch.id
		workspace.onAppear()
		await Task.yield()

		XCTAssertNotNil(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch)

		workspace.onDisappear()
		workspace.referencesViewModel.selectedBranchID = nil
		await Task.yield()
		XCTAssertNotNil(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch)

		workspace.onAppear()
		XCTAssertNil(workspace.focusedActionsViewModel.focusedActions.rebaseSelectedBranch)
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !condition() {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func makeSnapshot(changes: [WorkingTreeChange]) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: [],
			commits: [],
			branches: [],
			remotes: [],
			operationState: .normal,
			tags: [],
			stashes: [],
			fileTree: []
		)
	}
}
