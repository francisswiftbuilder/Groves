import DomainGitInterface
import XCTest

@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryStashes
@testable import Trees

@MainActor
final class WorkspaceStaleRequestTests: XCTestCase {
	func testIdenticalSnapshotDoesNotReloadSelectedWorkingTreeDiff() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				unstagedDiff: "first read",
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [change]))
		try await Task.sleep(for: .milliseconds(150))

		let callCount = await gate.callCount(of: label)
		XCTAssertEqual(callCount, 1)
	}

	func testChangedWorkingTreePayloadReloadsSelectedDiff() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let refreshedChange = WorkingTreeChange(
			path: change.path,
			previousPath: "README-old.md",
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change], diffGate: gate)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [refreshedChange]))

		try await waitUntilCallCount(2, of: label, in: gate)
	}

	func testIdenticalSnapshotDoesNotReloadSelectedConflictContent() async throws {
		let conflict = makeConflict()
		let operationState = makeOperationState(conflicts: [conflict])
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(operationState: operationState, diffGate: gate)
		)
		let label = GitDiffGateLabel.conflictContent(path: conflict.path)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(operationState: operationState))
		try await Task.sleep(for: .milliseconds(150))

		let callCount = await gate.callCount(of: label)
		XCTAssertEqual(callCount, 1)
	}

	func testChangedConflictPayloadReloadsSelectedContent() async throws {
		let conflict = makeConflict()
		let refreshedConflict = GitConflict(
			path: conflict.path,
			kind: .bothModified,
			hasBase: false,
			hasOurs: true,
			hasTheirs: true
		)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				operationState: makeOperationState(conflicts: [conflict]),
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.conflictContent(path: conflict.path)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(
			makeSnapshot(operationState: makeOperationState(conflicts: [refreshedConflict]))
		)

		try await waitUntilCallCount(2, of: label, in: gate)
	}

	func testRemovingSelectedConflictClearsSelectionAndContent() async throws {
		let conflict = makeConflict()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				operationState: makeOperationState(conflicts: [conflict])
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.conflictViewModel.content != nil }

		workspace.viewModel.didProduceSnapshot(makeSnapshot())

		XCTAssertTrue(workspace.changesViewModel.selectedChangeIDs.isEmpty)
		XCTAssertNil(workspace.changesViewModel.selectedConflict)
		XCTAssertNil(workspace.conflictViewModel.content)
	}

	func testRepositoryChangeResetsChangesStateAndInvalidatesMutation() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let conflict = makeConflict()
		let mutationGate = GitDiffGate(suspendsRequests: true)
		let contentGate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				operationState: makeOperationState(conflicts: [conflict]),
				mutationGate: mutationGate,
				contentGate: contentGate
			)
		)
		let firstRepository = URL(fileURLWithPath: "/tmp/First")
		let secondRepository = URL(fileURLWithPath: "/tmp/Second")

		await contentGate.resumeCall(0)
		workspace.viewModel.didChooseRepository(firstRepository)
		try await waitUntil {
			workspace.changesViewModel.changes == [change]
				&& workspace.changesViewModel.conflicts == [conflict]
		}
		workspace.changesViewModel.filterText = "readme"
		workspace.changesViewModel.didPresentDiscardConfirmation(for: [change])
		workspace.changesViewModel.didRequestStage([change])
		try await waitUntilTotalCallCount(1, in: mutationGate)
		XCTAssertTrue(workspace.changesViewModel.isLoading)

		workspace.viewModel.didChooseRepository(secondRepository)
		try await waitUntilTotalCallCount(2, in: contentGate)
		try await waitUntil { workspace.viewModel.repositoryURL == secondRepository }

		XCTAssertEqual(workspace.changesViewModel.filterText, "")
		XCTAssertNil(workspace.changesViewModel.pendingConfirmation)
		XCTAssertTrue(workspace.changesViewModel.selectedChangeIDs.isEmpty)
		XCTAssertTrue(workspace.changesViewModel.changes.isEmpty)
		XCTAssertTrue(workspace.changesViewModel.conflicts.isEmpty)
		XCTAssertFalse(workspace.changesViewModel.isLoading)
		XCTAssertNil(workspace.conflictViewModel.content)
		XCTAssertFalse(workspace.conflictViewModel.isLoading)
		XCTAssertFalse(workspace.changesDiffViewModel.isLoading)
		XCTAssertFalse(workspace.changesDiffViewModel.isApplyingAction)

		await contentGate.resumeCall(1)
		await mutationGate.resumeCall(0)
		try await waitUntilTotalCallCount(3, in: contentGate)
		await contentGate.resumeCall(2)
		try await Task.sleep(for: .milliseconds(150))
		XCTAssertFalse(workspace.changesViewModel.isLoading)
	}

	func testStaleStashDiffDoesNotOverwriteNewerOptions() async throws {
		let stash = GitStash(
			reference: "stash@{0}",
			hash: "abc1234",
			subject: "work in progress",
			date: nil
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(stashes: [stash], diffGate: gate)
		)
		let newerOptions = GitDiffOptions(ignoresWhitespace: true)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.stashesViewModel.stashes == [stash] }
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.diffPreferences.options = newerOptions
		workspace.viewModel.didChangeDiffOptions()
		try await waitUntilTotalCallCount(2, in: gate)

		await gate.resumeCall(1)
		try await waitUntil {
			workspace.stashesViewModel.diff == GitDiffGateLabel.stashDiff(options: newerOptions)
		}
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertEqual(
			workspace.stashesViewModel.diff,
			GitDiffGateLabel.stashDiff(options: newerOptions),
			"A stale stash diff must not overwrite the newer options result"
		)
	}

	func testStaleDiffRequestDoesNotFinishNewerLoadingState() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change], diffGate: gate)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilTotalCallCount(1, in: gate)
		XCTAssertTrue(workspace.changesDiffViewModel.isLoading)

		workspace.diffPreferences.options = GitDiffOptions(ignoresWhitespace: true)
		workspace.viewModel.didChangeDiffOptions()
		try await waitUntilTotalCallCount(2, in: gate)

		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(
			workspace.changesDiffViewModel.isLoading,
			"A stale diff request must not end the newer request's loading state"
		)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.isLoading == false }
	}

	func testStaleChangesMutationDoesNotFinishNewerLoadingState() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(changes: [change], mutationGate: gate)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }
		workspace.changesViewModel.didRequestStage([change])
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.changesViewModel.cancelTasks()
		workspace.changesViewModel.didRequestStage([change])
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(workspace.changesViewModel.isLoading)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesViewModel.isLoading == false }
	}

	func testStaleDiffMutationDoesNotFinishNewerApplyingState() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				unstagedDiff: "diff",
				mutationGate: gate
			)
		)
		let line = GitDiffLineSelection(oldLineNumber: 1, newLineNumber: 1)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.changesDiffViewModel.diff == "diff" }
		workspace.changesDiffViewModel.didRequestApplyDiffLine(line, action: .stage)
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.changesDiffViewModel.cancelTasks()
		workspace.changesDiffViewModel.didRequestApplyDiffLine(line, action: .stage)
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(workspace.changesDiffViewModel.isApplyingAction)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.isApplyingAction == false }
	}

	func testStaleConflictMutationDoesNotFinishNewerLoadingState() async throws {
		let conflict = makeConflict()
		let hunk = GitConflictHunk(index: 0, base: nil, current: "ours", incoming: "theirs")
		let gate = GitDiffGate(suspendsRequests: true)
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				operationState: makeOperationState(conflicts: [conflict]),
				mutationGate: gate
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { workspace.conflictViewModel.content != nil }
		workspace.conflictViewModel.didResolve(hunk, in: conflict, using: .current)
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.conflictViewModel.reset()
		workspace.conflictViewModel.didResolve(hunk, in: conflict, using: .current)
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		XCTAssertTrue(workspace.conflictViewModel.isLoading)
		await gate.resumeCall(1)
		try await waitUntil { workspace.conflictViewModel.isLoading == false }
	}

	private func makeConflict() -> GitConflict {
		GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
	}

	private func makeOperationState(conflicts: [GitConflict]) -> RepositoryOperationState {
		RepositoryOperationState(
			head: .attached,
			operation: RepositoryOperation(kind: .merge),
			conflicts: conflicts
		)
	}

	private func makeSnapshot(
		changes: [WorkingTreeChange] = [],
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

	private func waitUntilCallCount(
		_ count: Int,
		of label: String,
		in gate: GitDiffGate,
		message: String = "Timed out waiting for diff requests",
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.callCount(of: label) < count {
			guard clock.now < deadline else {
				XCTFail(message)
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func waitUntilTotalCallCount(
		_ count: Int,
		in gate: GitDiffGate,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await gate.totalCallCount() < count {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for gated requests")
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
