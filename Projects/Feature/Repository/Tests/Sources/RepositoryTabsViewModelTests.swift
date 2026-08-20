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
	func requestRepositoryRoot(at url: URL) async throws -> URL { url }
	func requestWorkingTreeChanges(at repositoryURL: URL) async throws -> [WorkingTreeChange] { [] }
	func requestAmendChanges(at repositoryURL: URL) async throws -> [GitAmendChange] { [] }
	func requestCommitHistory(at repositoryURL: URL) async throws -> [GitCommit] { [] }
	func requestCommitDiff(for commit: GitCommit, at repositoryURL: URL) async throws -> String { "" }
	func requestBranches(at repositoryURL: URL) async throws -> [GitBranch] { [] }
	func requestTags(at repositoryURL: URL) async throws -> [GitTag] { [] }
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
	func requestPull(at repositoryURL: URL) async throws {}
	func requestPush(at repositoryURL: URL) async throws {}
}
