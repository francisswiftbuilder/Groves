import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
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
