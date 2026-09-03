import DomainGitInterface
import XCTest

@testable import FeatureRepositoryChanges

@MainActor
final class CommitViewModelTests: XCTestCase {
	func testSnapshotAvailabilityUpdatesCommitActions() {
		let viewModel = makeViewModel()
		viewModel.subject = "Commit staged changes"

		viewModel.apply(
			makeSnapshot(
				changes: [
					WorkingTreeChange(
						path: "Sources/App.swift",
						previousPath: nil,
						indexState: .modified,
						workingTreeState: .unchanged
					)
				],
				commits: [makeCommit()]
			)
		)

		XCTAssertTrue(viewModel.hasStagedChanges)
		XCTAssertTrue(viewModel.hasCommits)
		XCTAssertTrue(viewModel.canCommit)
		XCTAssertTrue(viewModel.canAmendCommit)

		viewModel.apply(
			makeSnapshot(
				changes: [],
				commits: [makeCommit()],
				operationState: .detachedHead
			)
		)

		XCTAssertFalse(viewModel.hasStagedChanges)
		XCTAssertTrue(viewModel.isDetached)
		XCTAssertFalse(viewModel.canCommit)
		XCTAssertFalse(viewModel.canAmendCommit)
	}

	private func makeViewModel() -> CommitViewModel {
		CommitViewModel(
			dependencies: CommitViewModel.Dependencies(
				contentUseCase: ChangesContentUseCaseStub(),
				changesUseCase: ChangesUseCaseStub(),
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: CommitViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in },
				didChangeAmendingCommit: { _ in }
			)
		)
	}

	private func makeSnapshot(
		changes: [WorkingTreeChange],
		commits: [GitCommit],
		operationState: RepositoryOperationState = .normal
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: [],
			commits: commits,
			branches: [],
			remotes: [],
			operationState: operationState,
			tags: [],
			stashes: [],
			fileTree: []
		)
	}

	private func makeCommit() -> GitCommit {
		GitCommit(
			hash: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
			shortHash: "abcdefa",
			parentHashes: [],
			author: "Groves",
			date: .distantPast,
			references: ["HEAD"],
			subject: "Current commit",
			body: ""
		)
	}
}
