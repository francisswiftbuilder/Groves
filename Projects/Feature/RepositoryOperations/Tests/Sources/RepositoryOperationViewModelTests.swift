import DomainGitInterface
import XCTest

@testable import FeatureRepositoryOperations

@MainActor
final class RepositoryOperationViewModelTests: XCTestCase {
	func testMergeAndRebaseAvailabilityReflectsRepositoryState() {
		let currentBranch = makeBranch(name: "main", isCurrent: true)
		let featureBranch = makeBranch(name: "feature", isCurrent: false)
		let viewModel = makeViewModel()

		viewModel.apply(makeSnapshot(branches: [currentBranch, featureBranch]))

		XCTAssertTrue(viewModel.canMergeBranch(featureBranch))
		XCTAssertTrue(viewModel.canRebaseOnto(featureBranch))

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

		XCTAssertTrue(viewModel.canMergeBranch(featureBranch))
		XCTAssertFalse(viewModel.canRebaseOnto(featureBranch))
	}

	func testDetachedHeadDisablesBranchOperationsAndResetPresentation() {
		let currentBranch = makeBranch(name: "main", isCurrent: true)
		let featureBranch = makeBranch(name: "feature", isCurrent: false)
		let commit = makeCommit()
		let viewModel = makeViewModel()

		viewModel.apply(
			makeSnapshot(
				branches: [currentBranch, featureBranch],
				operationState: .detachedHead
			)
		)
		viewModel.didPresentReset(commit)

		XCTAssertFalse(viewModel.canMergeBranch(featureBranch))
		XCTAssertFalse(viewModel.canRebaseOnto(featureBranch))
		XCTAssertNil(viewModel.pendingResetCommit)
	}

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

		XCTAssertEqual(requestedConflict, first)
	}

	func testReleasingSyncViewModelCancelsRunningNetworkTask() async {
		let started = expectation(description: "Network task started")
		let cancelled = expectation(description: "Network task cancelled")
		let referencesUseCase = OperationsReferencesUseCaseStub { _ in
			started.fulfill()
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
				cancelled.fulfill()
			}
		}
		var viewModel: RepositorySyncViewModel? = RepositorySyncViewModel(
			dependencies: RepositorySyncViewModel.Dependencies(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: referencesUseCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: RepositorySyncViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in }
			)
		)
		weak let weakViewModel = viewModel

		viewModel?.didRequestFetchAll()
		await fulfillment(of: [started], timeout: 2)
		XCTAssertEqual(viewModel?.isLoading, true)
		XCTAssertEqual(viewModel?.activity, .fetchAll)

		viewModel = nil

		XCTAssertNil(weakViewModel)
		await fulfillment(of: [cancelled], timeout: 2)
	}

	func testCancellingSyncClearsActivity() async {
		let started = expectation(description: "Network task started")
		let cancelled = expectation(description: "Network task cancelled")
		let referencesUseCase = OperationsReferencesUseCaseStub { _ in
			started.fulfill()
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
				cancelled.fulfill()
			}
		}
		let viewModel = RepositorySyncViewModel(
			dependencies: RepositorySyncViewModel.Dependencies(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: referencesUseCase,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: RepositorySyncViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in }
			)
		)

		viewModel.didRequestFetchAll()
		await fulfillment(of: [started], timeout: 2)
		XCTAssertEqual(viewModel.activity, .fetchAll)
		for _ in 0..<200 where viewModel.presentedActivity != .fetchAll {
			try? await Task.sleep(for: .milliseconds(10))
		}
		XCTAssertEqual(viewModel.presentedActivity, .fetchAll)

		viewModel.didRequestCancelOperation()
		await fulfillment(of: [cancelled], timeout: 2)
		for _ in 0..<100 where viewModel.activity != nil {
			try? await Task.sleep(for: .milliseconds(10))
		}

		XCTAssertNil(viewModel.activity)
		XCTAssertNil(viewModel.presentedActivity)
		XCTAssertFalse(viewModel.isLoading)
	}

	func testShortSyncDoesNotPresentTransientActivity() async {
		let completed = expectation(description: "Network task completed")
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
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: RepositorySyncViewModel.Actions(
				didProduceSnapshot: { _ in completed.fulfill() },
				didReceiveError: { _ in }
			)
		)

		viewModel.didRequestFetchAll()
		await fulfillment(of: [completed], timeout: 2)
		try? await Task.sleep(for: .milliseconds(300))

		XCTAssertNil(viewModel.activity)
		XCTAssertNil(viewModel.presentedActivity)
		XCTAssertFalse(viewModel.isLoading)
	}

	func testSyncActivityUsesSpecificStatusAndCancellationLabels() {
		XCTAssertEqual(
			RepositorySyncViewModel.Activity.fetchRemote("origin").statusDescription,
			"Fetching origin"
		)
		XCTAssertEqual(
			RepositorySyncViewModel.Activity.pull("develop").statusDescription,
			"Pulling develop"
		)
		XCTAssertEqual(
			RepositorySyncViewModel.Activity.pushTags("origin").cancellationLabel,
			"Cancel Tag Push"
		)
		XCTAssertTrue(RepositorySyncViewModel.Activity.fetchAll.isFetch)
		XCTAssertTrue(RepositorySyncViewModel.Activity.pull("develop").isPull)
		XCTAssertTrue(RepositorySyncViewModel.Activity.push(nil).isPush)
	}

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
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: RepositorySyncViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in }
			)
		)
		let branch = makeBranch(name: "feature/push", isCurrent: true)

		viewModel.apply(makeSnapshot(branches: [branch]))
		XCTAssertEqual(
			viewModel.pushAction,
			.setUpstream(remoteName: "origin", branchName: branch.name)
		)

		viewModel.apply(makeSnapshot(branches: [branch], operationState: .detachedHead))
		XCTAssertEqual(viewModel.pushAction, .unavailable)
	}

	private func makeViewModel(
		didRequestViewConflicts: @escaping @MainActor (GitConflict) -> Void = { _ in }
	) -> RepositoryOperationViewModel {
		RepositoryOperationViewModel(
			dependencies: RepositoryOperationViewModel.Dependencies(
				contentUseCase: OperationsContentUseCaseStub(),
				referencesUseCase: OperationsReferencesUseCaseStub(),
				operationsUseCase: nil,
				repositoryURL: { URL(fileURLWithPath: "/tmp/Trees") }
			),
			actions: RepositoryOperationViewModel.Actions(
				didProduceSnapshot: { _ in },
				didReceiveError: { _ in },
				didRequestViewConflicts: didRequestViewConflicts
			)
		)
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
			author: "Trees",
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
