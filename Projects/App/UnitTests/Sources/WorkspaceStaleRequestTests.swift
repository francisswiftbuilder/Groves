import DomainGitInterface
import XCTest

@testable import FeatureRepositoryChanges
@testable import FeatureRepositoryStashes
@testable import Trees

@MainActor
final class WorkspaceStaleRequestTests: XCTestCase {
	func testSnapshotRefreshReloadsSelectedWorkingTreeDiff() async throws {
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

		try await waitUntilCallCount(
			2,
			of: label,
			in: gate,
			message: "An external file change must reload the selected diff"
		)
	}

	func testSnapshotRefreshReloadsSelectedConflictContent() async throws {
		let conflict = GitConflict(
			path: "Conflict.swift",
			kind: .bothModified,
			hasBase: true,
			hasOurs: true,
			hasTheirs: true
		)
		let operationState = RepositoryOperationState(
			head: .attached,
			operation: RepositoryOperation(kind: .merge),
			conflicts: [conflict]
		)
		let gate = GitDiffGate()
		let workspace = makeRepositoryWorkspace(
			repository: GitRepositoryStub(operationState: operationState, diffGate: gate)
		)
		let label = GitDiffGateLabel.conflictContent(path: conflict.path)

		workspace.viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntilCallCount(1, of: label, in: gate)

		workspace.viewModel.didProduceSnapshot(makeSnapshot(operationState: operationState))

		try await waitUntilCallCount(
			2,
			of: label,
			in: gate,
			message: "An external editor change must reload the selected conflict"
		)
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
