import DomainGitInterface
import Foundation
import Observation
import Testing

@testable import FeatureRepositoryHistory
@testable import Groves

@MainActor
struct RepositoryObservationTests {
	@Test
	func testFocusedActionsObserveBranchSelection() async {
		let branch = GitBranch(
			name: "feature/observation", shortHash: "1234567", upstream: nil, isCurrent: false)
		let workspace = makeRepositoryWorkspace()
		workspace.referencesViewModel.apply(makeSnapshot(branches: [branch]))
		workspace.referencesViewModel.selectedBranchID = nil
		#expect(workspace.focusedActionsViewModel.focusedActions.renameSelectedBranch == nil)

		await confirmation("Branch selection updates focused actions") { changed in
			withObservationTracking {
				_ = workspace.focusedActionsViewModel.focusedActions
			} onChange: {
				changed()
			}
			workspace.referencesViewModel.selectedBranchID = branch.id
		}

		#expect(workspace.focusedActionsViewModel.focusedActions.renameSelectedBranch != nil)
	}

	@Test
	func testFocusedActionsObserveRemoteSelection() async {
		let remote = GitRemote(name: "origin", fetchURL: nil, pushURL: nil)
		let workspace = makeRepositoryWorkspace()
		workspace.remotesViewModel.apply(makeSnapshot(remotes: [remote]))
		workspace.remotesViewModel.selectedRemoteID = nil
		#expect(workspace.focusedActionsViewModel.focusedActions.editSelectedRemote == nil)

		await confirmation("Remote selection updates focused actions") { changed in
			withObservationTracking {
				_ = workspace.focusedActionsViewModel.focusedActions
			} onChange: {
				changed()
			}
			workspace.remotesViewModel.selectedRemoteID = remote.id
		}

		#expect(workspace.focusedActionsViewModel.focusedActions.editSelectedRemote != nil)
	}

	@Test
	func testFocusedActionsObserveCommitSelection() async throws {
		let commit = GitCommit(
			hash: "1234567890abcdef", shortHash: "1234567", parentHashes: [], author: "Groves",
			date: .distantPast, references: [], subject: "Observe commit selection", body: ""
		)
		let workspace = makeRepositoryWorkspace()
		defer { workspace.onDisappear() }
		workspace.historyViewModel.apply(makeSnapshot(commits: [commit]))
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(2))
		while workspace.historyViewModel.commitGraphItems.isEmpty, clock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		try #require(workspace.historyViewModel.commitGraphItems.count == 1)
		workspace.historyViewModel.selectedCommitID = nil
		#expect(workspace.focusedActionsViewModel.focusedActions.cherryPickSelectedCommit == nil)

		await confirmation("Commit selection updates focused actions") { changed in
			withObservationTracking {
				_ = workspace.focusedActionsViewModel.focusedActions
			} onChange: {
				changed()
			}
			workspace.historyViewModel.selectedCommitID = commit.id
		}

		#expect(workspace.focusedActionsViewModel.focusedActions.cherryPickSelectedCommit != nil)
	}

	@Test
	func testFocusedActionsObserveConflictState() async {
		let conflict = GitConflict(
			path: "Conflict.swift", kind: .bothModified, hasBase: true, hasOurs: true, hasTheirs: true)
		let workspace = makeRepositoryWorkspace()
		#expect(workspace.focusedActionsViewModel.focusedActions.viewConflicts == nil)

		await confirmation("Repository conflicts update focused actions") { changed in
			withObservationTracking {
				_ = workspace.focusedActionsViewModel.focusedActions
			} onChange: {
				changed()
			}
			workspace.operationViewModel.apply(
				makeSnapshot(
					operationState: RepositoryOperationState(head: .attached, conflicts: [conflict]))
			)
		}

		#expect(workspace.focusedActionsViewModel.focusedActions.viewConflicts != nil)
	}

	private func makeSnapshot(
		commits: [GitCommit] = [],
		branches: [GitBranch] = [],
		remotes: [GitRemote] = [],
		operationState: RepositoryOperationState = .normal
	) -> RepositorySnapshot {
		RepositorySnapshot(
			changes: [], amendChanges: [], commits: commits, branches: branches, remotes: remotes,
			operationState: operationState, tags: [], stashes: [], fileTree: []
		)
	}
}
