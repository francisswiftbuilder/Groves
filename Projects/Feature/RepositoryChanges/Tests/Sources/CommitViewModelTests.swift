import DomainGitInterface
import XCTest

@testable import FeatureRepositoryChanges

@MainActor
final class CommitViewModelTests: XCTestCase {
	private actor SnapshotGate {
		private(set) var requestCount = 0
		private var continuations: [Int: CheckedContinuation<RepositorySnapshot, Error>] = [:]

		func load() async throws -> RepositorySnapshot {
			let index = requestCount
			requestCount += 1
			return try await withCheckedThrowingContinuation {
				continuations[index] = $0
			}
		}

		func resume(_ index: Int, returning snapshot: RepositorySnapshot) {
			continuations.removeValue(forKey: index)?.resume(returning: snapshot)
		}
	}

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

	func testCommitImmediatelyBlocksRepeatedSubmission() async throws {
		let gate = SnapshotGate()
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
				try await gate.load()
			})
		)
		defer { viewModel.onDisappear() }
		prepareCommit(viewModel)

		viewModel.didRequestCommit()
		XCTAssertTrue(viewModel.isLoading)
		XCTAssertFalse(viewModel.canCommit)
		viewModel.didRequestCommit()

		try await waitUntil { await gate.requestCount >= 1 }
		try await Task.sleep(for: .milliseconds(50))
		let requestCount = await gate.requestCount
		XCTAssertEqual(requestCount, 1)
		for index in 0..<requestCount {
			await gate.resume(index, returning: makeSnapshot(changes: [], commits: [makeCommit()]))
		}
	}

	func testCancelledCommitDoesNotEraseNewDraft() async throws {
		let gate = SnapshotGate()
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
				try await gate.load()
			})
		)
		prepareCommit(viewModel)
		viewModel.didRequestCommit()
		try await waitUntil { await gate.requestCount == 1 }

		viewModel.onDisappear()
		viewModel.subject = "New draft"
		viewModel.body = "Keep this description"
		await gate.resume(0, returning: makeSnapshot(changes: [], commits: [makeCommit()]))
		try await Task.sleep(for: .milliseconds(50))

		XCTAssertEqual(viewModel.subject, "New draft")
		XCTAssertEqual(viewModel.body, "Keep this description")
		XCTAssertFalse(viewModel.isLoading)
	}

	func testOldCommitDoesNotFinishNewerLoadingState() async throws {
		let gate = SnapshotGate()
		let completed = expectation(description: "Current commit completed")
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
				try await gate.load()
			}),
			didProduceSnapshot: { _ in completed.fulfill() }
		)
		prepareCommit(viewModel)
		viewModel.didRequestCommit()
		try await waitUntil { await gate.requestCount == 1 }
		viewModel.onDisappear()
		viewModel.subject = "Second commit"
		viewModel.didRequestCommit()
		try await waitUntil { await gate.requestCount == 2 }
		let snapshot = makeSnapshot(changes: [], commits: [makeCommit()])
		await gate.resume(0, returning: snapshot)
		try await Task.sleep(for: .milliseconds(50))

		XCTAssertTrue(viewModel.isLoading)
		XCTAssertEqual(viewModel.subject, "Second commit")
		await gate.resume(1, returning: snapshot)
		await fulfillment(of: [completed], timeout: 2)
		XCTAssertFalse(viewModel.isLoading)
		XCTAssertEqual(viewModel.subject, "")
	}

	func testSuccessfulCommitPreservesDraftEditedWhileRunning() async throws {
		let gate = SnapshotGate()
		let completed = expectation(description: "Commit completed")
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
				try await gate.load()
			}),
			didProduceSnapshot: { _ in completed.fulfill() }
		)
		prepareCommit(viewModel)
		viewModel.didRequestCommit()
		try await waitUntil { await gate.requestCount == 1 }
		viewModel.subject = "Next commit"
		viewModel.body = "Next description"

		await gate.resume(0, returning: makeSnapshot(changes: [], commits: [makeCommit()]))
		await fulfillment(of: [completed], timeout: 2)

		XCTAssertEqual(viewModel.subject, "Next commit")
		XCTAssertEqual(viewModel.body, "Next description")
	}

	func testFailedCommitPreservesDraftAndAllowsRetry() async {
		let recovered = expectation(description: "Repository state restored")
		let receivedError = expectation(description: "Commit error reported")
		let snapshot = makeSnapshot(changes: [], commits: [])
		let viewModel = makeViewModel(
			contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in snapshot }),
			changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
				throw GitRepositoryError.commandFailed("Set your commit identity")
			}),
			didProduceSnapshot: { _ in recovered.fulfill() },
			didReceiveError: { message in
				XCTAssertTrue(message.contains("Set your commit identity"))
				receivedError.fulfill()
			}
		)
		prepareCommit(viewModel)
		viewModel.body = "Description"

		viewModel.didRequestCommit()
		await fulfillment(of: [receivedError, recovered], timeout: 2)

		XCTAssertEqual(viewModel.subject, "Commit staged changes")
		XCTAssertEqual(viewModel.body, "Description")
		XCTAssertFalse(viewModel.isLoading)
		XCTAssertTrue(viewModel.canCommit)
	}

	func testCannotAmendBeforeFirstCommit() async {
		let amended = expectation(description: "Amend is unavailable without a commit")
		amended.isInverted = true
		let snapshot = makeSnapshot(changes: [], commits: [])
		let viewModel = makeViewModel(
			changesUseCase: ChangesUseCaseStub(amendOperation: { _ in
				amended.fulfill()
				return snapshot
			})
		)
		prepareCommit(viewModel)

		viewModel.didRequestAmendWithoutEditingMessage()

		await fulfillment(of: [amended], timeout: 0.1)
	}

	private func prepareCommit(_ viewModel: CommitViewModel) {
		viewModel.subject = "Commit staged changes"
		viewModel.apply(
			makeSnapshot(
				changes: [
					WorkingTreeChange(
						path: "README.md",
						previousPath: nil,
						indexState: .modified,
						workingTreeState: .unchanged
					)
				],
				commits: []
			)
		)
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while await !condition() {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for commit request")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func makeViewModel(
		contentUseCase: ChangesContentUseCaseStub = ChangesContentUseCaseStub(),
		changesUseCase: ChangesUseCaseStub = ChangesUseCaseStub(),
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in },
		didReceiveError: @escaping @MainActor (String) -> Void = { _ in }
	) -> CommitViewModel {
		CommitViewModel(
			dependencies: CommitViewModel.Dependencies(
				contentUseCase: contentUseCase,
				changesUseCase: changesUseCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: CommitViewModel.Actions(
				didProduceSnapshot: didProduceSnapshot,
				didReceiveError: didReceiveError,
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
