import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges

@MainActor
struct CommitViewModelTests {
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

	@Test
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

		#expect(viewModel.hasStagedChanges)
		#expect(viewModel.hasCommits)
		#expect(viewModel.canCommit)
		#expect(viewModel.canAmendCommit)

		viewModel.apply(
			makeSnapshot(
				changes: [],
				commits: [makeCommit()],
				operationState: .detachedHead
			)
		)

		#expect(!(viewModel.hasStagedChanges))
		#expect(viewModel.isDetached)
		#expect(!(viewModel.canCommit))
		#expect(!(viewModel.canAmendCommit))
	}

	@Test
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
		#expect(viewModel.isLoading)
		#expect(!(viewModel.canCommit))
		viewModel.didRequestCommit()

		try await waitUntil { await gate.requestCount >= 1 }
		try await Task.sleep(for: .milliseconds(50))
		let requestCount = await gate.requestCount
		#expect(requestCount == 1)
		for index in 0..<requestCount {
			await gate.resume(index, returning: makeSnapshot(changes: [], commits: [makeCommit()]))
		}
	}

	@Test
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

		#expect(viewModel.subject == "New draft")
		#expect(viewModel.body == "Keep this description")
		#expect(!(viewModel.isLoading))
	}

	@Test
	func testOldCommitDoesNotFinishNewerLoadingState() async throws {
		try await confirmation("Current commit completed") { completed in
			let gate = SnapshotGate()
			let viewModel = makeViewModel(
				changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
					try await gate.load()
				}),
				didProduceSnapshot: { _ in completed() }
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

			#expect(viewModel.isLoading)
			#expect(viewModel.subject == "Second commit")
			await gate.resume(1, returning: snapshot)
			try await waitUntil { !viewModel.isLoading }
			#expect(!(viewModel.isLoading))
			#expect(viewModel.subject == "")

		}
	}

	@Test
	func testSuccessfulCommitPreservesDraftEditedWhileRunning() async throws {
		try await confirmation("Commit completed") { completed in
			let gate = SnapshotGate()
			let viewModel = makeViewModel(
				changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
					try await gate.load()
				}),
				didProduceSnapshot: { _ in completed() }
			)
			prepareCommit(viewModel)
			viewModel.didRequestCommit()
			try await waitUntil { await gate.requestCount == 1 }
			viewModel.subject = "Next commit"
			viewModel.body = "Next description"

			await gate.resume(0, returning: makeSnapshot(changes: [], commits: [makeCommit()]))
			try await waitUntil { !viewModel.isLoading }

			#expect(viewModel.subject == "Next commit")
			#expect(viewModel.body == "Next description")

		}
	}

	@Test
	func testFailedCommitPreservesDraftAndAllowsRetry() async throws {
		try await confirmation("Repository state restored") { recovered in
			try await confirmation("Commit error reported") { receivedError in
				let snapshot = makeSnapshot(changes: [], commits: [])
				let viewModel = makeViewModel(
					contentUseCase: ChangesContentUseCaseStub(snapshotOperation: { _ in snapshot }),
					changesUseCase: ChangesUseCaseStub(commitOperation: { _, _, _, _ in
						throw GitRepositoryError.commandFailed("Set your commit identity")
					}),
					didProduceSnapshot: { _ in recovered() },
					didReceiveError: { message in
						#expect(message.contains("Set your commit identity"))
						receivedError()
					}
				)
				prepareCommit(viewModel)
				viewModel.body = "Description"

				viewModel.didRequestCommit()
				try await waitUntil { !viewModel.isLoading }

				#expect(viewModel.subject == "Commit staged changes")
				#expect(viewModel.body == "Description")
				#expect(!(viewModel.isLoading))
				#expect(viewModel.canCommit)

			}
		}
	}

	@Test
	func testCannotAmendBeforeFirstCommit() async throws {
		try await confirmation("Amend is unavailable without a commit", expectedCount: 0) { amended in
			let snapshot = makeSnapshot(changes: [], commits: [])
			let viewModel = makeViewModel(
				changesUseCase: ChangesUseCaseStub(amendOperation: { _ in
					amended()
					return snapshot
				})
			)
			prepareCommit(viewModel)

			viewModel.didRequestAmendWithoutEditingMessage()

			try await Task.sleep(for: .milliseconds(100))

		}
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
				Issue.record("Timed out waiting for commit request")
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
