import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
	func testStagedAndUnstagedSelectionsUseIndependentDiffSources() async throws {
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(
				changes: [change],
				stagedDiff: "cached diff",
				unstagedDiff: "working tree diff"
			)
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.changes == [change] }

		viewModel.selectedChangeIDs = [.staged(change.id)]
		viewModel.didChangeSelectedChanges()
		try await waitUntil { viewModel.diff == "cached diff" }
		XCTAssertEqual(viewModel.selectedFileState, .modified)

		viewModel.selectedChangeIDs = [.unstaged(change.id)]
		viewModel.didChangeSelectedChanges()
		try await waitUntil { viewModel.diff == "working tree diff" }
		XCTAssertEqual(viewModel.selectedFileState, .modified)
	}

	func testPushActionUsesUpstreamOrModelsRemoteChoice() async throws {
		let trackedBranch = GitBranch(
			name: "main",
			shortHash: "1234567",
			upstream: "origin/main",
			isCurrent: true
		)
		let untrackedBranch = GitBranch(
			name: "feature/push",
			shortHash: "7654321",
			upstream: nil,
			isCurrent: true
		)
		let origin = GitRemote(name: "origin", fetchURL: nil, pushURL: nil)
		let upstream = GitRemote(name: "upstream", fetchURL: nil, pushURL: nil)

		let trackedViewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(branches: [trackedBranch], remotes: [origin])
		)
		trackedViewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Tracked"))
		try await waitUntil { trackedViewModel.currentBranch == trackedBranch }
		XCTAssertEqual(trackedViewModel.pushAction, .upstream)

		let singleRemoteViewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(branches: [untrackedBranch], remotes: [origin])
		)
		singleRemoteViewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Single"))
		try await waitUntil { singleRemoteViewModel.currentBranch == untrackedBranch }
		XCTAssertEqual(
			singleRemoteViewModel.pushAction,
			.setUpstream(remoteName: "origin", branchName: "feature/push")
		)

		let multipleRemoteViewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(
				branches: [untrackedBranch],
				remotes: [origin, upstream]
			)
		)
		multipleRemoteViewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Multiple"))
		try await waitUntil { multipleRemoteViewModel.currentBranch == untrackedBranch }
		XCTAssertEqual(
			multipleRemoteViewModel.pushAction,
			.chooseRemote(
				remoteNames: ["origin", "upstream"],
				branchName: "feature/push"
			)
		)
	}

	func testRepositoryOperationStateIsLoadedIntoWorkspace() async throws {
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(operationState: .rebaseInProgress)
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Rebase"))
		try await waitUntil { viewModel.operationState == .rebaseInProgress }

		XCTAssertEqual(viewModel.currentBranchStatus, "Rebase in Progress")
	}

	func testMergeBranchUsesExplicitContextMenuBranch() async throws {
		let recorder = GitRepositoryRecorder()
		let currentBranch = GitBranch(
			name: "main",
			shortHash: "1234567",
			upstream: nil,
			isCurrent: true
		)
		let mergeBranch = GitBranch(
			name: "feature/merge",
			shortHash: "7654321",
			upstream: nil,
			isCurrent: false
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(
				recorder: recorder,
				branches: [currentBranch, mergeBranch]
			)
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.currentBranch == currentBranch }
		XCTAssertTrue(viewModel.canMergeBranch(mergeBranch))
		XCTAssertFalse(viewModel.canMergeBranch(currentBranch))

		viewModel.didRequestMergeBranch(mergeBranch)
		try await waitUntilRecorded(
			.merge(branchName: mergeBranch.name),
			by: recorder
		)
	}

	func testOpeningBranchFocusesLatestCommitInHistory() async throws {
		let commits = (0...10).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < 10 ? ["commit-\(index + 1)"] : [],
				author: "Trees Tests",
				date: Date(timeIntervalSince1970: TimeInterval(10 - index)),
				references: [],
				subject: "Commit \(index)",
				body: ""
			)
		}
		let branch = GitBranch(
			name: "feature/history-navigation",
			shortHash: "short-7",
			upstream: nil,
			isCurrent: false
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(commits: commits)
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.commitGraphItems.count == commits.count }

		viewModel.didOpenBranch(branch)
		try await waitUntil { viewModel.selectedCommitID == "commit-7" }

		XCTAssertEqual(viewModel.selectedSection, .history)
		XCTAssertEqual(viewModel.selectedBranchID, branch.id)
		XCTAssertEqual(viewModel.historyFocusRequest?.commitID, "commit-7")
	}

	func testOpeningRemoteBranchFocusesLatestCommitInHistory() async throws {
		let commit = GitCommit(
			hash: "remote-commit",
			shortHash: "remote",
			parentHashes: [],
			author: "Trees Tests",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: "Remote commit",
			body: ""
		)
		let branch = GitRemoteBranch(
			name: "main",
			fullName: "origin/main",
			remoteName: "origin",
			shortHash: commit.shortHash,
			hash: commit.hash
		)
		let remote = GitRemote(
			name: "origin",
			fetchURL: "https://example.com/Trees.git",
			pushURL: "https://example.com/Trees.git",
			branches: [branch]
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(commits: [commit], remotes: [remote])
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.commitGraphItems.count == 1 }

		viewModel.didOpenRemoteBranch(branch)

		XCTAssertEqual(viewModel.selectedSection, .history)
		XCTAssertEqual(viewModel.selectedRemoteID, remote.id)
		XCTAssertEqual(viewModel.historyFocusRequest?.commitID, commit.id)
	}

	func testOpeningTagFocusesDistantCommitInCompleteHistory() async throws {
		let lastIndex = 600
		let commits = (0...lastIndex).map { index in
			GitCommit(
				hash: "commit-\(index)",
				shortHash: "short-\(index)",
				parentHashes: index < lastIndex ? ["commit-\(index + 1)"] : [],
				author: "Trees Tests",
				date: Date(timeIntervalSince1970: TimeInterval(lastIndex - index)),
				references: [],
				subject: "Commit \(index)",
				body: ""
			)
		}
		let tag = GitTag(
			name: "deep-tag",
			shortHash: "short-\(lastIndex)",
			targetHash: "commit-\(lastIndex)",
			date: nil,
			subject: "Commit \(lastIndex)"
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(commits: commits, tags: [tag])
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.commitGraphItems.count == commits.count }

		viewModel.didOpenTag(tag)
		try await waitUntil { viewModel.selectedCommitID == tag.targetHash }

		XCTAssertEqual(viewModel.commitGraphItems.count, commits.count)
		XCTAssertEqual(viewModel.selectedSection, .history)
		XCTAssertEqual(viewModel.historyFocusRequest?.commitID, tag.targetHash)
	}

	func testViewModelOwnsChangeFilteringAndDiscardPresentation() async throws {
		let swiftChange = WorkingTreeChange(
			path: "Sources/GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let markdownChange = WorkingTreeChange(
			path: "README.md",
			previousPath: nil,
			indexState: .unchanged,
			workingTreeState: .modified
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(changes: [swiftChange, markdownChange])
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.changes.count == 2 }
		viewModel.changeFilterText = "gallery"

		XCTAssertEqual(viewModel.filteredStagedChanges, [swiftChange])
		XCTAssertEqual(viewModel.filteredUnstagedChanges, [swiftChange])

		viewModel.didPresentDiscardConfirmation(for: [swiftChange, markdownChange])

		XCTAssertEqual(viewModel.pendingDiscardChanges, [swiftChange, markdownChange])
		XCTAssertEqual(viewModel.discardConfirmationTitle, "Discard Changes to 2 Files?")

		viewModel.didDismissDiscardConfirmation()

		XCTAssertNil(viewModel.pendingDiscardChanges)
	}

	func testViewModelOwnsSidebarTreeAndNewBranchPresentationState() async {
		let viewModel = makeWorkspaceViewModel()
		let repositoryID = UUID()
		let branchesGroup = RepositorySidebarGroup(
			repositoryID: repositoryID,
			kind: .branches
		)

		viewModel.didPrepareSidebar(repositoryID: repositoryID)

		XCTAssertTrue(viewModel.expandedSidebarGroups.contains(branchesGroup))

		viewModel.setSidebarGroup(branchesGroup, isExpanded: false)
		viewModel.setTreeNode("Sources", isExpanded: true)
		viewModel.didPresentNewBranch()
		viewModel.newBranchName = "feature/view-model-state"

		XCTAssertFalse(viewModel.expandedSidebarGroups.contains(branchesGroup))
		XCTAssertTrue(viewModel.expandedTreeNodeIDs.contains("Sources"))
		XCTAssertTrue(viewModel.isPresentingNewBranch)
		XCTAssertEqual(viewModel.newBranchName, "feature/view-model-state")

		viewModel.didDismissNewBranch()

		XCTAssertFalse(viewModel.isPresentingNewBranch)
		XCTAssertTrue(viewModel.newBranchName.isEmpty)
	}

	func testSelectionEventsPublishAfterSwiftUIUpdateCycle() async throws {
		let change = WorkingTreeChange(
			path: "GalleryView.swift",
			previousPath: nil,
			indexState: .modified,
			workingTreeState: .modified
		)
		let viewModel = makeWorkspaceViewModel(
			repository: GitRepositoryStub(changes: [change])
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Trees"))
		try await waitUntil { viewModel.changes == [change] }
		await viewModel.didSelectChanges([.unstaged(change.id)])

		XCTAssertEqual(viewModel.selectedChangeIDs, [.unstaged(change.id)])
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

	private func waitUntilRecorded(
		_ event: GitRepositoryRecorder.Event,
		by recorder: GitRepositoryRecorder,
		timeout: Duration = .seconds(2)
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while !(await recorder.recordedEvents().contains(event)) {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for repository event")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
	}
}
