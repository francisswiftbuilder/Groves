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

		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		XCTAssertEqual(viewModel.tabs.map(\.id), [first.id, second.id])
		XCTAssertEqual(viewModel.selectedTabID, second.id)
	}

	func testSelectingCurrentRepositoryDoesNotPersistSelectionAgain() {
		let repository = makeSavedRepository(name: "Current", position: 0, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didSelectTab(repository.id)

		XCTAssertTrue(store.selectionRequestIDs.isEmpty)
	}

	func testWindowRestorationReturnsPrimaryAndAdditionalRepositoriesOnlyOnce() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let viewModel = makeRepositoryTabsViewModel(
			savedRepositoryStore: SavedRepositoryStoreSpy(repositories: [first, second])
		)

		let restoration = viewModel.requestWindowRestoration(currentRepositoryID: nil)

		XCTAssertEqual(
			restoration,
			RepositoryWindowRestoration(
				primaryRepositoryID: first.id,
				additionalRepositoryIDs: [second.id]
			)
		)
		XCTAssertNil(viewModel.requestWindowRestoration(currentRepositoryID: nil))
	}

	func testChoosingRepositorySavesAndOpensRepository() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/ExistingTrees", isDirectory: true)
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		var openedRepositoryID: UUID?

		viewModel.didChooseRepository(repositoryURL) { repositoryID in
			openedRepositoryID = repositoryID
		}

		try await waitUntil { viewModel.tabs.count == 1 }

		XCTAssertEqual(viewModel.tabs.first?.repository.url, repositoryURL)
		XCTAssertEqual(openedRepositoryID, viewModel.tabs.first?.id)
		XCTAssertEqual(store.selectedRepositoryID, viewModel.tabs.first?.id)
	}

	func testCloningRepositorySavesAndOpensClonedRepository() async throws {
		let clonedRepositoryURL = URL(fileURLWithPath: "/tmp/ClonedTrees", isDirectory: true)
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(
			repository: GitRepositoryStub(clonedRepositoryURL: clonedRepositoryURL),
			savedRepositoryStore: store
		)
		var openedRepositoryID: UUID?

		viewModel.didRequestCloneRepository(
			from: "https://github.com/owner/ClonedTrees.git",
			into: URL(fileURLWithPath: "/tmp", isDirectory: true)
		) { repositoryID in
			openedRepositoryID = repositoryID
		}

		try await waitUntil { viewModel.tabs.count == 1 }

		XCTAssertEqual(viewModel.tabs.first?.repository.url, clonedRepositoryURL)
		XCTAssertEqual(openedRepositoryID, viewModel.tabs.first?.id)
		XCTAssertEqual(store.selectedRepositoryID, viewModel.tabs.first?.id)
	}

	func testSidebarSelectionActivationOwnsWorkspaceNavigation() {
		let repository = makeSavedRepository(name: "Current", position: 0, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let selection = RepositorySidebarSelection.section(
			repositoryID: repository.id,
			section: .history
		)

		XCTAssertEqual(viewModel.selectedWorkspace?.selectedSection, .changes)

		viewModel.didActivateSidebarSelection(selection)

		XCTAssertEqual(viewModel.selectedWorkspace?.selectedSection, .history)
		XCTAssertTrue(store.selectionRequestIDs.isEmpty)
	}

	func testWindowViewModelOwnsImporterCloneAndSidebarState() async {
		let viewModel = RepositoryWindowViewModel()
		let repositoryID = UUID()
		let selection = RepositorySidebarSelection.section(
			repositoryID: repositoryID,
			section: .history
		)

		viewModel.cloneRemoteURL = "  https://github.com/owner/Trees.git  "
		viewModel.didPresentCloneDestinationImporter()

		XCTAssertTrue(viewModel.isFolderImporterPresented)
		if case .clone(let remoteURL) = viewModel.consumeFolderImportRequest() {
			XCTAssertEqual(remoteURL, "https://github.com/owner/Trees.git")
		} else {
			XCTFail("Expected a clone folder import request")
		}
		XCTAssertFalse(viewModel.isFolderImporterPresented)

		await viewModel.didSelectSidebarItem(selection)

		XCTAssertEqual(viewModel.sidebarSelection, selection)
	}

	func testClosingSelectedRepositorySelectsNeighborAndPersistsSelection() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didRequestCloseTab(first.id)

		XCTAssertEqual(viewModel.tabs.map(\.id), [second.id])
		XCTAssertEqual(viewModel.selectedTabID, second.id)
		XCTAssertEqual(store.removedRepositoryIDs, [first.id])
		XCTAssertEqual(store.selectedRepositoryID, second.id)
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while condition() == false {
			guard clock.now < deadline else {
				XCTFail("Timed out waiting for condition")
				return
			}
			try await Task.sleep(for: .milliseconds(10))
		}
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
