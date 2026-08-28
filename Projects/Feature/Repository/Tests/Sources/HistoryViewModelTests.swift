import DomainGitInterface
import XCTest

@testable import FeatureRepository
@testable import FeatureRepositoryHistory

@MainActor
final class HistoryViewModelTests: XCTestCase {
	func testCommitGraphLayoutIsBuiltOffTheMainActor() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = [makeCommit(index: 0), makeCommit(index: 1)]

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: commits))

		XCTAssertTrue(
			historyViewModel.commitGraphItems.isEmpty,
			"The graph layout must not be built while the snapshot is applied"
		)

		try await waitUntil { historyViewModel.commitGraphItems.isEmpty == false }

		XCTAssertEqual(historyViewModel.commitGraphItems.map(\.commit), commits)
		XCTAssertEqual(historyViewModel.displayedCommitGraphItems.map(\.commit), commits)
	}

	func testResetDiscardsAPendingCommitGraphLayout() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [makeCommit(index: 0)]))
		historyViewModel.reset()
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(
			historyViewModel.commitGraphItems.isEmpty,
			"A layout requested before the reset must not be published afterwards"
		)
		XCTAssertTrue(historyViewModel.displayedCommitGraphItems.isEmpty)
	}

	func testSupersededSnapshotNeverRequestsItsCommitDiff() async throws {
		let seed = makeCommit(index: 0)
		let superseded = makeCommit(index: 1)
		let latest = makeCommit(index: 2)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(commits: [seed], diffGate: gate)
		)
		let historyViewModel = workspace.historyViewModel

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { historyViewModel.commitGraphItems.map(\.commit) == [seed] }

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [superseded]))
		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [latest]))

		try await waitUntil { historyViewModel.commitGraphItems.map(\.commit) == [latest] }
		try await waitUntilCallCount(1, of: GitDiffGateLabel.commitDiff(hash: latest.hash), in: gate)

		let supersededDiffCount = await gate.callCount(
			of: GitDiffGateLabel.commitDiff(hash: superseded.hash)
		)

		XCTAssertEqual(
			supersededDiffCount,
			0,
			"A superseded layout must not request its own commit diff"
		)
	}

	func testSnapshotArrivingDuringASearchReRunsTheFilter() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let matching = makeCommit(index: 1, subject: "Add the release checklist")

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [makeCommit(index: 0)]))
		try await waitUntil { historyViewModel.commitGraphItems.isEmpty == false }

		historyViewModel.didChangeSearchText("release")
		try await waitUntil { historyViewModel.displayedCommitGraphItems.isEmpty }

		workspace.viewModel.didProduceSnapshot(
			makeSnapshot(commits: [matching, makeCommit(index: 0)])
		)

		try await waitUntil {
			historyViewModel.displayedCommitGraphItems.map(\.commit) == [matching]
		}

		XCTAssertEqual(historyViewModel.commitGraphItems.count, 2)
		XCTAssertEqual(historyViewModel.searchText, "release")
	}

	func testSearchResultsOfASupersededSnapshotAreDiscarded() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let staleMatch = makeCommit(index: 1, subject: "Add the release checklist")
		let freshMatch = makeCommit(index: 2, subject: "Cut the release branch")

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [staleMatch]))
		try await waitUntil { historyViewModel.commitGraphItems.isEmpty == false }

		historyViewModel.didChangeSearchText("release")
		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [freshMatch]))

		try await waitUntil {
			historyViewModel.displayedCommitGraphItems.map(\.commit) == [freshMatch]
		}
		try await Task.sleep(for: .milliseconds(200))

		XCTAssertEqual(
			historyViewModel.displayedCommitGraphItems.map(\.commit),
			[freshMatch],
			"A search filtered over superseded commits must not be published"
		)
	}

	func testSelectionIsPreservedByCommitHashAcrossSnapshots() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let first = makeCommit(index: 0)
		let second = makeCommit(index: 1)
		let latest = makeCommit(index: 2)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [first, second]))
		try await waitUntil { historyViewModel.commitGraphItems.count == 2 }

		await historyViewModel.didSelectCommit(second.id)
		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: [latest, first, second]))

		try await waitUntil { historyViewModel.commitGraphItems.count == 3 }

		XCTAssertEqual(
			historyViewModel.selectedCommitID,
			second.id,
			"A new snapshot must keep the selected commit hash"
		)
	}

	func testSearchIsDebouncedBeforeFiltering() async throws {
		let workspace = makeRepositoryWorkspace()
		let historyViewModel = workspace.historyViewModel
		let commits = [makeCommit(index: 0), makeCommit(index: 1, subject: "Cut the release")]

		workspace.viewModel.didProduceSnapshot(makeSnapshot(commits: commits))
		try await waitUntil { historyViewModel.commitGraphItems.count == 2 }

		historyViewModel.didChangeSearchText("rel")
		historyViewModel.didChangeSearchText("release")

		XCTAssertEqual(
			historyViewModel.displayedCommitGraphItems.count,
			2,
			"The filter must not run before the debounce interval elapses"
		)

		try await waitUntil {
			historyViewModel.displayedCommitGraphItems.map(\.commit) == [commits[1]]
		}
	}

	private func makeCommit(index: Int, subject: String = "Commit") -> GitCommit {
		GitCommit(
			hash: String(repeating: "\(index)", count: 12),
			shortHash: String(repeating: "\(index)", count: 7),
			parentHashes: [],
			author: "Trees",
			date: .distantPast,
			references: [],
			subject: subject,
			body: ""
		)
	}

	private func makeSnapshot(commits: [GitCommit]) -> RepositorySnapshot {
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
	}

	private func waitUntilCallCount(
		_ count: Int,
		of label: String,
		in gate: GitDiffGate,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.callCount(of: label) < count {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for diff requests")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
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
}
