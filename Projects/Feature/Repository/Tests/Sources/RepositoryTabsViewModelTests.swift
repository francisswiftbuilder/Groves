import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

@MainActor
final class RepositoryTabsViewModelTests: XCTestCase {
	func testRestoreSelectsPreviouslySelectedRepository() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: false)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])

		let viewModel = RepositoryTabsViewModel(
			gitRepository: GitRepositoryStub(),
			savedRepositoryStore: store
		)

		XCTAssertEqual(viewModel.tabs.map(\.id), [first.id, second.id])
		XCTAssertEqual(viewModel.selectedTabID, second.id)
	}

	func testClosingSelectedRepositorySelectsNeighborAndPersistsSelection() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = RepositoryTabsViewModel(
			gitRepository: GitRepositoryStub(),
			savedRepositoryStore: store
		)

		viewModel.didRequestCloseTab(first.id)

		XCTAssertEqual(viewModel.tabs.map(\.id), [second.id])
		XCTAssertEqual(viewModel.selectedTabID, second.id)
		XCTAssertEqual(store.removedRepositoryIDs, [first.id])
		XCTAssertEqual(store.selectedRepositoryID, second.id)
	}

	private func makeSavedRepository(
		name: String,
		position: Int,
		isSelected: Bool
	) -> SavedRepository {
		SavedRepository(
			id: UUID(),
			name: name,
			url: URL(fileURLWithPath: "/tmp/\(name)"),
			position: position,
			isSelected: isSelected
		)
	}
}

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
		XCTAssertEqual(viewModel.selectedHistoryBranchID, branch.id)
		XCTAssertNil(viewModel.selectedTagID)
		XCTAssertEqual(viewModel.historyFocusRequest?.commitID, "commit-7")
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
		XCTAssertNil(viewModel.selectedHistoryBranchID)
		XCTAssertEqual(viewModel.selectedTagID, tag.id)
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

final class RepositoryFileSystemMonitorTests: XCTestCase {
	func testEventsEmitsWhenNestedFileChanges() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		let nestedDirectoryURL = directoryURL.appending(path: "Nested", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: nestedDirectoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let eventExpectation = expectation(description: "Receives a recursive file system event")
		let events = RepositoryFileSystemMonitor.events(at: directoryURL)
		let eventTask = Task {
			for await _ in events {
				eventExpectation.fulfill()
				return
			}
		}
		defer {
			eventTask.cancel()
		}

		try Data("updated".utf8).write(to: nestedDirectoryURL.appending(path: "File.txt"))
		await fulfillment(of: [eventExpectation], timeout: 3)
	}
}

@MainActor
private final class SavedRepositoryStoreSpy: SavedRepositoryStore {
	private(set) var repositories: [SavedRepository]
	private(set) var removedRepositoryIDs: [UUID] = []
	private(set) var selectedRepositoryID: UUID?

	init(repositories: [SavedRepository]) {
		self.repositories = repositories
	}

	func requestRepositories() throws -> [SavedRepository] {
		repositories
	}

	func requestSaveRepository(at url: URL) throws -> SavedRepository {
		let repository = SavedRepository(
			id: UUID(),
			name: url.lastPathComponent,
			url: url,
			position: repositories.count,
			isSelected: false
		)
		repositories.append(repository)
		return repository
	}

	func requestRemoveRepository(id: UUID) throws {
		removedRepositoryIDs.append(id)
		repositories.removeAll { $0.id == id }
	}

	func requestSelectRepository(id: UUID?) throws {
		selectedRepositoryID = id
	}
}

private struct GitRepositoryStub: GitRepository {
	let commits: [GitCommit]
	let tags: [GitTag]

	init(commits: [GitCommit] = [], tags: [GitTag] = []) {
		self.commits = commits
		self.tags = tags
	}

	func requestRepositoryRoot(at url: URL) async throws -> URL { url }
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] { [] }
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] { [] }
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] { commits }
	func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String { "" }
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] { [] }
	func requestRemotes(at repositoryURL: URL) async throws -> [GitRemote] { [] }
	func requestTags(at repositoryURL: URL) async throws -> [GitTag] { tags }
	func requestStashes(at repositoryURL: URL) async throws -> [GitStash] { [] }
	func requestFileTree(at repositoryURL: URL) async throws -> [RepositoryTreeNode] { [] }
	func requestFileContents(at path: String, in repositoryURL: URL) async throws -> Data { Data() }
	func requestDiff(for change: WorkingTreeChange, at repositoryURL: URL) async throws -> String {
		""
	}
	func requestAmendDiff(for change: GitAmendChange, at repositoryURL: URL) async throws
		-> String
	{
		""
	}
	func requestStage(path: String, at repositoryURL: URL) async throws {}
	func requestUnstage(path: String, at repositoryURL: URL) async throws {}
	func requestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction,
		for change: WorkingTreeChange,
		at repositoryURL: URL
	) async throws {}
	func requestDiscard(change: WorkingTreeChange, at repositoryURL: URL) async throws {}
	func requestUnstageFromAmend(change: GitAmendChange, at repositoryURL: URL) async throws {}
	func requestCommit(
		subject: String,
		body: String,
		amend: Bool,
		at repositoryURL: URL
	) async throws {}
	func requestSwitchBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestDeleteBranch(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateTag(named name: String, message: String, at repositoryURL: URL) async throws {}
	func requestDeleteTag(named name: String, at repositoryURL: URL) async throws {}
	func requestCreateStash(message: String, at repositoryURL: URL) async throws {}
	func requestApplyStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPopStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestDropStash(_ stash: GitStash, at repositoryURL: URL) async throws {}
	func requestPull(at repositoryURL: URL) async throws {}
	func requestPush(at repositoryURL: URL) async throws {}
}
