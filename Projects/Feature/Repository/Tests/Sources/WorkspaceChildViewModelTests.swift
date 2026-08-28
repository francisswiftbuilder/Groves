import DomainGitInterface
import XCTest

@testable import FeatureRepository
@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryHistory
@testable import FeatureRepositoryStashes

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
	}

	func testSnapshotIsDistributedAcrossChildViewModels() {
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
			author: "Trees",
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

		XCTAssertEqual(changesViewModel.changes, [change])
		XCTAssertEqual(historyViewModel.commitGraphItems.map(\.commit), [commit])
		XCTAssertEqual(referencesViewModel.branches, [branch])
		XCTAssertTrue(changesDiffViewModel.preferences === preferences)
	}

	func testHistoryViewModelCancelsPendingDebouncedSearch() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = [
			GitCommit(
				hash: "111111111111",
				shortHash: "1111111",
				parentHashes: [],
				author: "Trees",
				date: .distantPast,
				references: ["HEAD"],
				subject: "First",
				body: ""
			),
			GitCommit(
				hash: "222222222222",
				shortHash: "2222222",
				parentHashes: [],
				author: "Trees",
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
		historyViewModel.didChangeSearchText("missing")
		historyViewModel.cancelTasks()
		try await Task.sleep(for: .milliseconds(200))

		XCTAssertEqual(historyViewModel.displayedCommitGraphItems.count, commits.count)
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
