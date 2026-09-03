import CoreRepositoryDiff
import DomainGitInterface
import XCTest

@testable import FeatureRepositoryHistory

@MainActor
final class HistoryViewModelTests: XCTestCase {
	func testCommitGraphLayoutIsBuiltOffTheMainActor() async throws {
		let viewModel = makeViewModel()
		let commits = [makeCommit(index: 0), makeCommit(index: 1)]

		viewModel.apply(makeSnapshot(commits: commits))

		XCTAssertTrue(viewModel.commitGraphItems.isEmpty)
		try await waitUntil { viewModel.commitGraphItems.isEmpty == false }
		XCTAssertEqual(viewModel.commitGraphItems.map(\.commit), commits)
		XCTAssertEqual(viewModel.displayedCommitGraphItems.map(\.commit), commits)
	}

	func testResetDiscardsAPendingCommitGraphLayout() async throws {
		let viewModel = makeViewModel()

		viewModel.apply(makeSnapshot(commits: [makeCommit(index: 0)]))
		viewModel.reset()
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(viewModel.commitGraphItems.isEmpty)
		XCTAssertTrue(viewModel.displayedCommitGraphItems.isEmpty)
	}

	func testSupersededSnapshotNeverRequestsItsCommitDiff() async throws {
		let seed = makeCommit(index: 0)
		let superseded = makeCommit(index: 1)
		let latest = makeCommit(index: 2)
		let useCase = HistoryChangesUseCaseStub()
		let viewModel = makeViewModel(useCase: useCase)

		viewModel.apply(makeSnapshot(commits: [seed]))
		try await waitUntil { viewModel.commitGraphItems.map(\.commit) == [seed] }
		try await waitUntilCallCount(1, commitHash: seed.hash, in: useCase)

		viewModel.apply(makeSnapshot(commits: [superseded]))
		viewModel.apply(makeSnapshot(commits: [latest]))

		try await waitUntil { viewModel.commitGraphItems.map(\.commit) == [latest] }
		try await waitUntilCallCount(1, commitHash: latest.hash, in: useCase)
		let supersededRequestCount = await useCase.callCount(forCommit: superseded.hash)
		XCTAssertEqual(supersededRequestCount, 0)
	}

	func testSnapshotArrivingDuringASearchReRunsTheFilter() async throws {
		let viewModel = makeViewModel()
		let matching = makeCommit(index: 1, subject: "Add the release checklist")

		viewModel.apply(makeSnapshot(commits: [makeCommit(index: 0)]))
		try await waitUntil { viewModel.commitGraphItems.isEmpty == false }
		viewModel.didChangeSearchText("release")
		try await waitUntil { viewModel.displayedCommitGraphItems.isEmpty }
		viewModel.apply(makeSnapshot(commits: [matching, makeCommit(index: 0)]))

		try await waitUntil { viewModel.displayedCommitGraphItems.map(\.commit) == [matching] }
		XCTAssertEqual(viewModel.commitGraphItems.count, 2)
		XCTAssertEqual(viewModel.searchText, "release")
	}

	func testSearchResultsOfASupersededSnapshotAreDiscarded() async throws {
		let viewModel = makeViewModel()
		let staleMatch = makeCommit(index: 1, subject: "Add the release checklist")
		let freshMatch = makeCommit(index: 2, subject: "Cut the release branch")

		viewModel.apply(makeSnapshot(commits: [staleMatch]))
		try await waitUntil { viewModel.commitGraphItems.isEmpty == false }
		viewModel.didChangeSearchText("release")
		viewModel.apply(makeSnapshot(commits: [freshMatch]))

		try await waitUntil { viewModel.displayedCommitGraphItems.map(\.commit) == [freshMatch] }
		try await Task.sleep(for: .milliseconds(200))
		XCTAssertEqual(viewModel.displayedCommitGraphItems.map(\.commit), [freshMatch])
	}

	func testSelectionIsPreservedByCommitHashAcrossSnapshots() async throws {
		let viewModel = makeViewModel()
		let first = makeCommit(index: 0)
		let second = makeCommit(index: 1)
		let latest = makeCommit(index: 2)

		viewModel.apply(makeSnapshot(commits: [first, second]))
		try await waitUntil { viewModel.commitGraphItems.count == 2 }
		await viewModel.didSelectCommit(second.id)
		viewModel.apply(makeSnapshot(commits: [latest, first, second]))

		try await waitUntil { viewModel.commitGraphItems.count == 3 }
		XCTAssertEqual(viewModel.selectedCommitID, second.id)
	}

	func testSearchIsDebouncedBeforeFiltering() async throws {
		let viewModel = makeViewModel()
		let commits = [makeCommit(index: 0), makeCommit(index: 1, subject: "Cut the release")]

		viewModel.apply(makeSnapshot(commits: commits))
		try await waitUntil { viewModel.commitGraphItems.count == 2 }
		viewModel.didChangeSearchText("rel")
		viewModel.didChangeSearchText("release")

		XCTAssertEqual(viewModel.displayedCommitGraphItems.count, 2)
		try await waitUntil { viewModel.displayedCommitGraphItems.map(\.commit) == [commits[1]] }
	}

	func testRunningLayoutDoesNotRetainViewModel() {
		let commits = (0..<10_000).map { makeCommit(index: $0) }
		weak var weakViewModel: HistoryViewModel?
		autoreleasepool {
			let viewModel = makeViewModel()
			viewModel.apply(makeSnapshot(commits: commits))
			weakViewModel = viewModel
		}

		XCTAssertNil(weakViewModel)
	}

	func testWorkingTreeAvailabilityUpdatesWithoutCommitHistoryChanges() {
		let viewModel = makeViewModel()
		let commits = [makeCommit(index: 0)]
		viewModel.apply(makeSnapshot(commits: commits))

		viewModel.apply(
			makeSnapshot(
				commits: commits,
				changes: [
					WorkingTreeChange(
						path: "Sources/App.swift",
						previousPath: nil,
						indexState: .unchanged,
						workingTreeState: .modified
					)
				]
			)
		)

		XCTAssertTrue(viewModel.checkoutAvailability.hasWorkingTreeChanges)
	}

	private func makeViewModel(
		useCase: HistoryChangesUseCaseStub = HistoryChangesUseCaseStub()
	) -> HistoryViewModel {
		HistoryViewModel(
			dependencies: HistoryViewModel.Dependencies(
				changesUseCase: useCase,
				preferences: WorkspaceDiffPreferences(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: HistoryViewModel.Actions(
				didReceiveError: { _ in },
				didRequestPresentation: {},
				didFocusBranch: { _ in },
				didFocusRemoteBranch: { _ in }
			)
		)
	}

	private func makeCommit(index: Int, subject: String = "Commit") -> GitCommit {
		GitCommit(
			hash: String(repeating: "\(index)", count: 12),
			shortHash: String(repeating: "\(index)", count: 7),
			parentHashes: [],
			author: "Groves",
			date: .distantPast,
			references: [],
			subject: subject,
			body: ""
		)
	}

	private func makeSnapshot(
		commits: [GitCommit],
		changes: [WorkingTreeChange] = []
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
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
		commitHash: String,
		in useCase: HistoryChangesUseCaseStub,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await useCase.callCount(forCommit: commitHash) < count {
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
