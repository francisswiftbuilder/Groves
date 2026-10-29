import DomainGitInterface
import Foundation
import Synchronization
import Testing

@testable import FeatureRepositoryOperations

@MainActor
struct RepositoryOperationViewModelTests {
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

		func fail(_ index: Int, with error: any Error) {
			continuations.removeValue(forKey: index)?.resume(throwing: error)
		}
	}

	@Test
	func testSyncIgnoresRepeatedRequestsWhileRunning() async throws {
		let gate = SnapshotGate()
		let viewModel = makeSyncViewModel(
			referencesUseCase: OperationsReferencesUseCaseStub { _ in try await gate.load() }
		)
		defer { viewModel.onDisappear() }

		viewModel.didRequestFetchAll()
		viewModel.didRequestFetchAll()
		try await waitUntil { await gate.requestCount >= 1 }
		try await Task.sleep(for: .milliseconds(50))
		let requestCount = await gate.requestCount
		#expect(requestCount == 1)
		for index in 0..<requestCount {
			await gate.resume(index, returning: makeSnapshot())
		}
	}

	@Test
	func testCancelledSyncDoesNotPublishLateSuccess() async throws {
		try await confirmation("Cancelled sync must not publish a snapshot", expectedCount: 0) {
			published in
			let gate = SnapshotGate()
			let viewModel = makeSyncViewModel(
				referencesUseCase: OperationsReferencesUseCaseStub { _ in try await gate.load() },
				didProduceSnapshot: { _ in published() }
			)
			viewModel.didRequestFetchAll()
			try await waitUntil { await gate.requestCount == 1 }

			viewModel.didRequestCancelOperation()
			await gate.resume(0, returning: makeSnapshot())
			try await Task.sleep(for: .milliseconds(100))

			#expect(!(viewModel.isLoading))

		}
	}

	@Test
	func testPushBlocksDuplicateRequestsAndCanRetryAfterFailure() async throws {
		try await confirmation("Failed push refreshes repository state") { recovered in
			try await confirmation("Push retry completed") { completed in
				let gate = SnapshotGate()
				let snapshot = makeSnapshot(branches: [makeBranch(name: "main", isCurrent: true)])
				var referencesUseCase = OperationsReferencesUseCaseStub(
					pushActionOperation: { _, _, _ in .upstream }
				)
				referencesUseCase.pushOperation = { _ in
					try await gate.load()
				}
				var receivedErrors: [String] = []
				var publishedSnapshotCount = 0
				let viewModel = RepositorySyncViewModel(
					dependencies: .init(
						contentUseCase: OperationsContentUseCaseStub(snapshotOperation: { _ in snapshot }),
						referencesUseCase: referencesUseCase,
						repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
					),
					actions: .init(
						didProduceSnapshot: { _ in
							if publishedSnapshotCount == 0 {
								recovered()
							} else {
								completed()
							}
							publishedSnapshotCount += 1
						},
						didReceiveError: { receivedErrors.append($0) }
					)
				)
				viewModel.apply(snapshot)
				viewModel.didRequestPush()
				viewModel.didRequestPush()
				try await waitUntil { await gate.requestCount >= 1 }
				try await Task.sleep(for: .milliseconds(50))
				let requestCount = await gate.requestCount
				#expect(requestCount == 1)
				await gate.fail(
					0, with: GitRepositoryError.authentication("Repository write access denied"))
				try await waitUntil { publishedSnapshotCount == 1 && !viewModel.isLoading }
				#expect(!(viewModel.isLoading))
				#expect(receivedErrors.count == 1)
				#expect(receivedErrors.first?.contains("write access denied") == true)

				viewModel.didRequestPush()
				try await waitUntil { await gate.requestCount == 2 }
				await gate.resume(1, returning: snapshot)
				try await waitUntil { !viewModel.isLoading }
				#expect(!(viewModel.isLoading))

			}
		}
	}

	@Test
	func testOldRecoveryDoesNotOverwriteNewerSnapshot() async throws {
		let gate = SnapshotGate()
		let currentSnapshot = makeSnapshot(branches: [makeBranch(name: "current", isCurrent: true)])
		var publishedBranchNames: [String] = []
		let viewModel = makeSyncViewModel(
			contentUseCase: OperationsContentUseCaseStub(snapshotOperation: { _ in
				try await gate.load()
			}),
			referencesUseCase: OperationsReferencesUseCaseStub { _ in
				throw GitRepositoryError.network("Connection interrupted")
			},
			didProduceSnapshot: { snapshot in
				publishedBranchNames.append(contentsOf: snapshot.branches.map(\.name))
			}
		)
		viewModel.didRequestFetchAll()
		try await waitUntil { await gate.requestCount == 1 }
		viewModel.reset()
		viewModel.didRequestFetchAll()
		try await waitUntil { await gate.requestCount == 2 }
		await gate.resume(1, returning: currentSnapshot)
		try await waitUntil { !viewModel.isLoading }

		let oldSnapshot = makeSnapshot(branches: [makeBranch(name: "old", isCurrent: true)])
		await gate.resume(0, returning: oldSnapshot)
		try await Task.sleep(for: .milliseconds(50))

		#expect(publishedBranchNames == ["current"])
	}

	@Test
	func testMergeAndRebaseAvailabilityReflectsRepositoryState() {
		let currentBranch = makeBranch(name: "main", isCurrent: true)
		let featureBranch = makeBranch(name: "feature", isCurrent: false)
		let viewModel = makeViewModel()

		viewModel.apply(makeSnapshot(branches: [currentBranch, featureBranch]))

		#expect(viewModel.canMergeBranch(featureBranch))
		#expect(viewModel.canRebaseOnto(featureBranch))

		viewModel.apply(
			makeSnapshot(
				changes: [
					WorkingTreeChange(
						path: "README.md",
						previousPath: nil,
						indexState: .unchanged,
						workingTreeState: .modified
					)
				],
				branches: [currentBranch, featureBranch]
			)
		)

		#expect(viewModel.canMergeBranch(featureBranch))
		#expect(!(viewModel.canRebaseOnto(featureBranch)))
	}

	@Test
	func testViewConflictsOutputsTheFirstConflict() {
		let first = makeConflict(path: "Sources/First.swift")
		let second = makeConflict(path: "Sources/Second.swift")
		var requestedConflict: GitConflict?
		let viewModel = makeViewModel(didRequestViewConflicts: { requestedConflict = $0 })

		viewModel.apply(
			makeSnapshot(
				operationState: RepositoryOperationState(
					head: .attached,
					conflicts: [first, second]
				)
			)
		)
		viewModel.didViewConflicts()

		#expect(requestedConflict == first)
	}

	@Test
	func testReleasingSyncViewModelCancelsRunningNetworkTask() async throws {
		try await confirmation("Network task started") { started in
			try await confirmation("Network task cancelled") { cancelled in
				let events = Mutex((started: false, cancelled: false))
				let referencesUseCase = OperationsReferencesUseCaseStub { _ in
					started()
					events.withLock { $0.started = true }
					return try await withTaskCancellationHandler {
						try await Task.sleep(for: .seconds(60))
						return RepositorySnapshot(
							changes: [],
							amendChanges: [],
							commits: [],
							branches: [],
							remotes: [],
							operationState: .normal,
							tags: [],
							stashes: [],
							fileTree: []
						)
					} onCancel: {
						cancelled()
						events.withLock { $0.cancelled = true }
					}
				}
				var viewModel: RepositorySyncViewModel? = RepositorySyncViewModel(
					dependencies: RepositorySyncViewModel.Dependencies(
						contentUseCase: OperationsContentUseCaseStub(),
						referencesUseCase: referencesUseCase,
						repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
					),
					actions: RepositorySyncViewModel.Actions(
						didProduceSnapshot: { _ in },
						didReceiveError: { _ in }
					)
				)
				weak let weakViewModel = viewModel

				viewModel?.didRequestFetchAll()
				try await waitUntil { events.withLock { $0.started } }
				#expect(viewModel?.isLoading == true)
				#expect(viewModel?.activity == .fetchAll)

				viewModel = nil

				#expect(weakViewModel == nil)
				try await waitUntil { events.withLock { $0.cancelled } }

			}
		}
	}

	@Test
	func testCancellingSyncClearsActivity() async throws {
		try await confirmation("Network task started") { started in
			try await confirmation("Network task cancelled") { cancelled in
				let events = Mutex((started: false, cancelled: false))
				let referencesUseCase = OperationsReferencesUseCaseStub { _ in
					started()
					events.withLock { $0.started = true }
					return try await withTaskCancellationHandler {
						try await Task.sleep(for: .seconds(60))
						return RepositorySnapshot(
							changes: [],
							amendChanges: [],
							commits: [],
							branches: [],
							remotes: [],
							operationState: .normal,
							tags: [],
							stashes: [],
							fileTree: []
						)
					} onCancel: {
						cancelled()
						events.withLock { $0.cancelled = true }
					}
				}
				let viewModel = RepositorySyncViewModel(
					dependencies: RepositorySyncViewModel.Dependencies(
						contentUseCase: OperationsContentUseCaseStub(),
						referencesUseCase: referencesUseCase,
						repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
					),
					actions: RepositorySyncViewModel.Actions(
						didProduceSnapshot: { _ in },
						didReceiveError: { _ in }
					)
				)

				viewModel.didRequestFetchAll()
				try await waitUntil { events.withLock { $0.started } }
				#expect(viewModel.activity == .fetchAll)
				for _ in 0..<200 where viewModel.presentedActivity != .fetchAll {
					try? await Task.sleep(for: .milliseconds(10))
				}
				#expect(viewModel.presentedActivity == .fetchAll)

				viewModel.didRequestCancelOperation()
				try await waitUntil { events.withLock { $0.cancelled } }
				for _ in 0..<100 where viewModel.activity != nil {
					try? await Task.sleep(for: .milliseconds(10))
				}

				#expect(viewModel.activity == nil)
				#expect(viewModel.presentedActivity == nil)
				#expect(!(viewModel.isLoading))

			}
		}
	}

	@Test
	func testShortSyncDoesNotPresentTransientActivity() async throws {
		try await confirmation("Network task completed") { completed in
			let referencesUseCase = OperationsReferencesUseCaseStub { _ in
				RepositorySnapshot(
					changes: [],
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
			let viewModel = RepositorySyncViewModel(
				dependencies: RepositorySyncViewModel.Dependencies(
					contentUseCase: OperationsContentUseCaseStub(),
					referencesUseCase: referencesUseCase,
					repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
				),
				actions: RepositorySyncViewModel.Actions(
					didProduceSnapshot: { _ in completed() },
					didReceiveError: { _ in }
				)
			)

			viewModel.didRequestFetchAll()
			try await waitUntil { !viewModel.isLoading }
			try? await Task.sleep(for: .milliseconds(300))

			#expect(viewModel.activity == nil)
			#expect(viewModel.presentedActivity == nil)
			#expect(!(viewModel.isLoading))

		}
	}

	@Test
	func testSyncActivityUsesSpecificStatusAndCancellationLabels() {
		#expect(
			RepositorySyncViewModel.Activity.fetchRemote("origin").statusDescription == "Fetching origin")
		#expect(RepositorySyncViewModel.Activity.pull("develop").statusDescription == "Pulling develop")
		#expect(
			RepositorySyncViewModel.Activity.pushTags("origin").cancellationLabel == "Cancel Tag Push")
		#expect(RepositorySyncViewModel.Activity.fetchAll.isFetch)
		#expect(RepositorySyncViewModel.Activity.pull("develop").isPull)
		#expect(RepositorySyncViewModel.Activity.push(nil).isPush)
	}

	@Test
	func testSyncPushActionUpdatesWhenOnlyBranchStateChanges() {
		let useCase = OperationsReferencesUseCaseStub(
			pushActionOperation: { branch, _, operationState in
				guard !operationState.isDetached, let branch else { return .unavailable }
				return .setUpstream(remoteName: "origin", branchName: branch.name)
			}
		)
		let viewModel = RepositorySyncViewModel(
			dependencies: RepositorySyncViewModel.Dependencies(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: useCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: RepositorySyncViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in }
			)
		)
		let branch = makeBranch(name: "feature/push", isCurrent: true)

		viewModel.apply(makeSnapshot(branches: [branch]))
		#expect(viewModel.pushAction == .setUpstream(remoteName: "origin", branchName: branch.name))

		viewModel.apply(makeSnapshot(branches: [branch], operationState: .detachedHead))
		#expect(viewModel.pushAction == .unavailable)
	}

	private func makeViewModel(
		didRequestViewConflicts: @escaping @MainActor (GitConflict) -> Void = { _ in }
	) -> RepositoryOperationViewModel {
		RepositoryOperationViewModel(
			dependencies: RepositoryOperationViewModel.Dependencies(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: OperationsReferencesUseCaseStub(),
				operationsUseCase: nil,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: RepositoryOperationViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in },
				didRequestViewConflicts: didRequestViewConflicts
			)
		)
	}

	private func makeSyncViewModel(
		contentUseCase: OperationsContentUseCaseStub = OperationsContentUseCaseStub(),
		referencesUseCase: OperationsReferencesUseCaseStub,
		didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void = { _ in }
	) -> RepositorySyncViewModel {
		RepositorySyncViewModel(
			dependencies: .init(
				contentUseCase: contentUseCase,
				referencesUseCase: referencesUseCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Groves") }
			),
			actions: .init(
				didProduceSnapshot: didProduceSnapshot,
				didReceiveError: { _ in }
			)
		)
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while await !condition() {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for network request")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func makeSnapshot(
		changes: [WorkingTreeChange] = [],
		branches: [GitBranch] = [],
		operationState: RepositoryOperationState = .normal
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: changes,
			amendChanges: [],
			commits: [],
			branches: branches,
			remotes: [],
			operationState: operationState,
			tags: [],
			stashes: [],
			fileTree: []
		)
	}

	private func makeBranch(name: String, isCurrent: Bool) -> GitBranch {
		GitBranch(
			name: name,
			shortHash: "abc1234",
			upstream: nil,
			isCurrent: isCurrent
		)
	}

	private func makeCommit() -> GitCommit {
		GitCommit(
			hash: "abc123456789",
			shortHash: "abc1234",
			parentHashes: [],
			author: "Groves",
			date: .distantPast,
			references: [],
			subject: "Commit",
			body: ""
		)
	}

	private func makeConflict(path: String) -> GitConflict {
		GitConflict(
			path: path,
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
	}
}
