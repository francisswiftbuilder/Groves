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
		let viewModel = WorkspaceViewModel(
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

		let trackedViewModel = WorkspaceViewModel(
			repository: GitRepositoryStub(branches: [trackedBranch], remotes: [origin])
		)
		trackedViewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Tracked"))
		try await waitUntil { trackedViewModel.currentBranch == trackedBranch }
		XCTAssertEqual(trackedViewModel.pushAction, .upstream)

		let singleRemoteViewModel = WorkspaceViewModel(
			repository: GitRepositoryStub(branches: [untrackedBranch], remotes: [origin])
		)
		singleRemoteViewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Single"))
		try await waitUntil { singleRemoteViewModel.currentBranch == untrackedBranch }
		XCTAssertEqual(
			singleRemoteViewModel.pushAction,
			.setUpstream(remoteName: "origin", branchName: "feature/push")
		)

		let multipleRemoteViewModel = WorkspaceViewModel(
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
		let viewModel = WorkspaceViewModel(
			repository: GitRepositoryStub(operationState: .rebaseInProgress)
		)

		viewModel.didChooseRepository(URL(fileURLWithPath: "/tmp/Rebase"))
		try await waitUntil { viewModel.operationState == .rebaseInProgress }

		XCTAssertEqual(viewModel.currentBranchStatus, "Rebase in Progress")
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
		let viewModel = WorkspaceViewModel(repository: GitRepositoryStub(commits: commits))

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
		let viewModel = WorkspaceViewModel(
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
		let viewModel = WorkspaceViewModel(
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
