import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryStashes
@testable import Groves

@MainActor
struct WorkspaceStaleRequestTests {
	@Test
	func testIdenticalSnapshotRevalidatesSelectedWorkingTreeDiff() async throws {
		let change = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let responses = GitRepositoryStub.ResponseSequence(["first read", "second read"])
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				changes: [change],
				diffResponses: responses,
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.workingTree(options: GitDiffOptions())

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntilCallCount(1, of: label, in: gate)
		await gate.resumeCall(0)
		try await waitUntil { workspace.changesDiffViewModel.diff == "first read" }

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [change]))
		try await waitUntilCallCount(2, of: label, in: gate)

		#expect(workspace.changesDiffViewModel.diff == "first read")
		#expect(workspace.changesDiffViewModel.isLoading)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.diff == "second read" }
		#expect(!(workspace.changesDiffViewModel.isLoading))
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(changes: [refreshedChange]))

		try await waitUntilCallCount(2, of: label, in: gate)
	}

	@Test
	func testIdenticalSnapshotRevalidatesSelectedConflictContent() async throws {
		let conflict = makeConflict()
		let operationState = makeOperationState(conflicts: [conflict])
		let firstContent = GitConflictContent(
			base: nil,
			current: "first current",
			incoming: "first incoming",
			workingTree: nil,
			hunks: []
		)
		let secondContent = GitConflictContent(
			base: nil,
			current: "second current",
			incoming: "second incoming",
			workingTree: nil,
			hunks: []
		)
		let gate = GitDiffGate(suspendsRequests: true)
		let responses = GitRepositoryStub.ResponseSequence([firstContent, secondContent])
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				operationState: operationState,
				conflictContentResponses: responses,
				diffGate: gate
			)
		)
		let label = GitDiffGateLabel.conflictContent(path: conflict.path)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntilCallCount(1, of: label, in: gate)
		await gate.resumeCall(0)
		try await waitUntil { workspace.conflictViewModel.content == firstContent }

		workspace.viewModel.didProduceSnapshot(makeSnapshot(operationState: operationState))
		try await waitUntilCallCount(2, of: label, in: gate)

		#expect(workspace.conflictViewModel.content == firstContent)
		#expect(workspace.conflictViewModel.isLoadingContent)
		await gate.resumeCall(1)
		try await waitUntil { workspace.conflictViewModel.content == secondContent }
		#expect(!(workspace.conflictViewModel.isLoadingContent))
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(
			makeSnapshot(operationState: makeOperationState(conflicts: [refreshedConflict]))
		)

		try await waitUntilCallCount(2, of: label, in: gate)
	}

	@Test
	func testRemovingSelectedConflictClearsSelectionAndContent() async throws {
		let conflict = makeConflict()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(
				operationState: makeOperationState(conflicts: [conflict])
			)
		)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.conflictViewModel.content != nil }

		workspace.viewModel.didProduceSnapshot(makeSnapshot())

		#expect(workspace.changesViewModel.selectedChangeIDs.isEmpty)
		#expect(workspace.changesViewModel.selectedConflict == nil)
		#expect(workspace.conflictViewModel.content == nil)
	}

	@Test
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
		#expect(workspace.changesViewModel.isLoading)

		workspace.viewModel.didChooseRepository(secondRepository)
		try await waitUntilTotalCallCount(2, in: contentGate)
		try await waitUntil { workspace.viewModel.repositoryURL == secondRepository }

		#expect(workspace.changesViewModel.filterText == "")
		#expect(workspace.changesViewModel.pendingConfirmation == nil)
		#expect(workspace.changesViewModel.selectedChangeIDs.isEmpty)
		#expect(workspace.changesViewModel.changes.isEmpty)
		#expect(workspace.changesViewModel.conflicts.isEmpty)
		#expect(!(workspace.changesViewModel.isLoading))
		#expect(workspace.conflictViewModel.content == nil)
		#expect(!(workspace.conflictViewModel.isLoading))
		#expect(!(workspace.changesDiffViewModel.isLoading))
		#expect(!(workspace.changesDiffViewModel.isApplyingAction))

		await contentGate.resumeCall(1)
		await mutationGate.resumeCall(0)
		try await waitUntilTotalCallCount(3, in: contentGate)
		await contentGate.resumeCall(2)
		try await Task.sleep(for: .milliseconds(150))
		#expect(!(workspace.changesViewModel.isLoading))
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
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

		#expect(
			workspace.stashesViewModel.diff == GitDiffGateLabel.stashDiff(options: newerOptions),
			"A stale stash diff must not overwrite the newer options result")
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntilTotalCallCount(1, in: gate)
		#expect(workspace.changesDiffViewModel.isLoading)

		workspace.diffPreferences.options = GitDiffOptions(ignoresWhitespace: true)
		workspace.viewModel.didChangeDiffOptions()
		try await waitUntilTotalCallCount(2, in: gate)

		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(
			workspace.changesDiffViewModel.isLoading,
			"A stale diff request must not end the newer request's loading state")
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.isLoading == false }
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesViewModel.changes == [change] }
		workspace.changesViewModel.didRequestStage([change])
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.changesViewModel.cancelTasks()
		workspace.changesViewModel.didRequestStage([change])
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(workspace.changesViewModel.isLoading)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesViewModel.isLoading == false }
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.changesDiffViewModel.diff == "diff" }
		workspace.changesDiffViewModel.didRequestApplyDiffLine(line, action: .stage)
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.changesDiffViewModel.cancelTasks()
		workspace.changesDiffViewModel.didRequestApplyDiffLine(line, action: .stage)
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(workspace.changesDiffViewModel.isApplyingAction)
		await gate.resumeCall(1)
		try await waitUntil { workspace.changesDiffViewModel.isApplyingAction == false }
	}

	@Test
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

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Groves"))
		try await waitUntil { workspace.conflictViewModel.content != nil }
		workspace.conflictViewModel.didResolve(hunk, in: conflict, using: .current)
		try await waitUntilTotalCallCount(1, in: gate)

		workspace.conflictViewModel.reset()
		workspace.conflictViewModel.didResolve(hunk, in: conflict, using: .current)
		try await waitUntilTotalCallCount(2, in: gate)
		await gate.resumeCall(0)
		try await Task.sleep(for: .milliseconds(150))

		#expect(workspace.conflictViewModel.isLoading)
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
				Issue.record(Comment(rawValue: message))
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
				Issue.record("Timed out waiting for gated requests")
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
				Issue.record("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
