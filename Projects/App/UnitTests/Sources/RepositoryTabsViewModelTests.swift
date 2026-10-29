import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryChanges
@testable import Groves

@MainActor
struct RepositoryTabsViewModelTests {
	@Test
	func testRestoreSelectsPreviouslySelectedRepository() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: false)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])

		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		#expect(viewModel.tabs.map(\.id) == [first.id, second.id])
		#expect(viewModel.selectedTabID == second.id)
	}

	@Test
	func testSelectingCurrentRepositoryDoesNotPersistSelectionAgain() {
		let repository = makeSavedRepository(name: "Current", position: 0, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didSelectTab(repository.id)

		#expect(store.selectionRequestIDs.isEmpty)
	}

	@Test
	func testWindowRestorationReturnsPrimaryAndAdditionalRepositoriesOnlyOnce() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let viewModel = makeRepositoryTabsViewModel(
			savedRepositoryStore: SavedRepositoryStoreSpy(repositories: [first, second])
		)

		let restoration = viewModel.requestWindowRestoration(currentRepositoryID: nil)

		#expect(
			restoration
				== RepositoryWindowRestoration(
					primaryRepositoryID: first.id,
					additionalRepositoryIDs: [second.id]
				))
		#expect(viewModel.requestWindowRestoration(currentRepositoryID: nil) == nil)
	}

	@Test
	func testChoosingRepositorySavesAndOpensRepository() async throws {
		let repositoryURL = URL(fileURLWithPath: "/tmp/ExistingGroves", isDirectory: true)
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		var openedRepositoryID: UUID?

		viewModel.didChooseRepository(
			repositoryURL,
			actions: .init { repositoryID in
				openedRepositoryID = repositoryID
			}
		)

		try await waitUntil { viewModel.tabs.count == 1 }

		#expect(viewModel.tabs.first?.repository.url == repositoryURL)
		#expect(openedRepositoryID == viewModel.tabs.first?.id)
		#expect(store.selectedRepositoryID == viewModel.tabs.first?.id)
	}

	@Test
	func testChoosingMultipleRepositoriesSavesAndOpensEveryRepository() async throws {
		let repositoryURLs = [
			URL(fileURLWithPath: "/tmp/FirstGroves", isDirectory: true),
			URL(fileURLWithPath: "/tmp/SecondGroves", isDirectory: true),
		]
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		var openedRepositoryIDs: [UUID] = []

		viewModel.didChooseRepositories(
			repositoryURLs,
			actions: .init { repositoryID in
				openedRepositoryIDs.append(repositoryID)
			}
		)

		try await waitUntil { viewModel.tabs.count == repositoryURLs.count }

		#expect(viewModel.tabs.map(\.repository.url) == repositoryURLs)
		#expect(openedRepositoryIDs == viewModel.tabs.map(\.id))
		#expect(store.selectedRepositoryID == viewModel.tabs.last?.id)
	}

	@Test
	func testCloningRepositorySavesAndOpensClonedRepository() async throws {
		let clonedRepositoryURL = URL(fileURLWithPath: "/tmp/ClonedGroves", isDirectory: true)
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(
			repository: GitRepositoryStub(clonedRepositoryURL: clonedRepositoryURL),
			savedRepositoryStore: store
		)
		var openedRepositoryID: UUID?

		viewModel.didRequestCloneRepository(
			from: "https://github.com/owner/ClonedGroves.git",
			into: URL(fileURLWithPath: "/tmp", isDirectory: true),
			actions: .init { repositoryID in
				openedRepositoryID = repositoryID
			}
		)

		try await waitUntil { viewModel.tabs.count == 1 }

		#expect(viewModel.tabs.first?.repository.url == clonedRepositoryURL)
		#expect(openedRepositoryID == viewModel.tabs.first?.id)
		#expect(store.selectedRepositoryID == viewModel.tabs.first?.id)
	}

	@Test
	func testSidebarSelectionActivationOwnsWorkspaceNavigation() {
		let repository = makeSavedRepository(name: "Current", position: 0, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let selection = RepositorySidebarSelection.section(
			repositoryID: repository.id,
			section: .history
		)

		#expect(viewModel.selectedWorkspace?.selectedSection == .changes)

		viewModel.didActivateSidebarSelection(selection)

		#expect(viewModel.selectedWorkspace?.selectedSection == .history)
		#expect(store.selectionRequestIDs.isEmpty)
	}

	@Test
	func testWindowViewModelOwnsImporterCloneAndSidebarState() async {
		let viewModel = RepositoryWindowViewModel()
		let repositoryID = UUID()
		let selection = RepositorySidebarSelection.section(
			repositoryID: repositoryID,
			section: .history
		)

		viewModel.cloneRemoteURL = "  https://github.com/owner/Groves.git  "
		viewModel.didPresentCloneDestinationImporter()

		#expect(viewModel.isFolderImporterPresented)
		if case .clone(let remoteURL) = viewModel.consumeFolderImportRequest() {
			#expect(remoteURL == "https://github.com/owner/Groves.git")
		} else {
			Issue.record("Expected a clone folder import request")
		}
		#expect(!(viewModel.isFolderImporterPresented))

		await viewModel.didSelectSidebarItem(selection)

		#expect(viewModel.sidebarSelection == selection)
	}

	@Test
	func testDismissingRepositoryImporterAllowsItToBePresentedAgain() {
		let viewModel = RepositoryWindowViewModel()

		viewModel.didPresentRepositoryImporter()

		#expect(viewModel.isFolderImporterPresented)
		#expect(viewModel.folderImportRequest?.allowsMultipleSelection == true)

		viewModel.didDismissFolderImporter()

		#expect(!(viewModel.isFolderImporterPresented))
		#expect(viewModel.folderImportRequest?.allowsMultipleSelection == true)

		viewModel.didPresentRepositoryImporter()

		#expect(viewModel.isFolderImporterPresented)
		#expect(viewModel.folderImportRequest?.allowsMultipleSelection == true)
	}

	@Test
	func testCloneDestinationImporterOnlyAllowsOneSelection() {
		let viewModel = RepositoryWindowViewModel()
		viewModel.cloneRemoteURL = "https://github.com/owner/Groves.git"

		viewModel.didPresentCloneDestinationImporter()

		#expect(viewModel.isFolderImporterPresented)
		#expect(viewModel.folderImportRequest?.allowsMultipleSelection == false)
	}

	@Test
	func testClosingSelectedRepositorySelectsNeighborAndPersistsSelection() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didRequestCloseTab(first.id)

		#expect(viewModel.tabs.map(\.id) == [second.id])
		#expect(viewModel.selectedTabID == second.id)
		#expect(store.removedRepositoryIDs == [first.id])
		#expect(store.selectedRepositoryID == second.id)
	}

	@Test
	func testPreparingBackgroundRepositoryDoesNotChangeSavedSelection() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let background = makeSavedRepository(name: "Background", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, background])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didPrepareTab(background.id)
		viewModel.didActivateSidebarSelection(.section(repositoryID: background.id, section: .history))

		#expect(viewModel.selectedTabID == first.id)
		#expect(store.selectionRequestIDs.isEmpty)
		#expect(viewModel.tab(id: background.id)?.hasLoadedContent == true)
		#expect(viewModel.tab(id: background.id)?.workspace.viewModel.selectedSection == .history)
	}

	@Test
	func testFailedSelectionPreservesPreviousSelectionAndCanBeRetried() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		store.selectionError = SavedRepositoryStoreError.persistenceFailed

		viewModel.didSelectTab(second.id)

		#expect(viewModel.selectedTabID == first.id)
		#expect(viewModel.alertMessage != nil)
		store.selectionError = nil
		viewModel.didSelectTab(second.id)

		#expect(viewModel.selectedTabID == second.id)
		#expect(store.selectedRepositoryID == second.id)
	}

	@Test
	func testFailedRemovalPreservesSavedRepositories() {
		let repository = makeSavedRepository(name: "Current", position: 0, isSelected: true)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		store.removalError = SavedRepositoryStoreError.persistenceFailed

		viewModel.didRequestCloseTab(repository.id)

		#expect(viewModel.tabs.map(\.id) == [repository.id])
		#expect(store.repositories.map(\.id) == [repository.id])
		#expect(viewModel.selectedTabID == repository.id)
		#expect(viewModel.alertMessage != nil)
	}

	@Test
	func testRestorationIgnoresUnknownCurrentRepositoryID() {
		let repository = makeSavedRepository(name: "Saved", position: 0, isSelected: true)
		let viewModel = makeRepositoryTabsViewModel(
			savedRepositoryStore: SavedRepositoryStoreSpy(repositories: [repository])
		)

		let restoration = viewModel.requestWindowRestoration(currentRepositoryID: UUID())

		#expect(restoration?.primaryRepositoryID == repository.id)
		#expect(restoration?.additionalRepositoryIDs == [])
	}

	@Test
	func testReopeningMovedRepositoryUpdatesWorkspaceWithoutLosingDraftOrNavigation() async throws {
		let repository = makeSavedRepository(name: "Original", position: 0, isSelected: true)
		let movedURL = URL(fileURLWithPath: "/tmp/Moved", isDirectory: true)
		let movedRepository = SavedRepository(
			id: repository.id,
			name: "Moved",
			url: movedURL,
			position: repository.position,
			isSelected: true
		)
		let store = SavedRepositoryStoreSpy(repositories: [repository])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)
		let workspace = try #require(viewModel.tab(id: repository.id)?.workspace)
		workspace.commitViewModel.subject = "Uncommitted subject"
		workspace.commitViewModel.body = "Uncommitted body"
		workspace.viewModel.didSelectSection(.history)
		store.savedRepositoryOverride = movedRepository

		viewModel.didChooseRepository(movedURL, actions: .init(didOpenRepository: { _ in }))
		try await waitUntil {
			viewModel.tab(id: repository.id)?.repository.url == movedURL
				&& workspace.viewModel.repositoryURL == movedURL
				&& !workspace.viewModel.isLoading
		}

		#expect(viewModel.tabs.count == 1)
		#expect(viewModel.tab(id: repository.id)?.repository.name == "Moved")
		#expect(viewModel.tab(id: repository.id)?.workspace === workspace)
		#expect(workspace.commitViewModel.subject == "Uncommitted subject")
		#expect(workspace.commitViewModel.body == "Uncommitted body")
		#expect(workspace.viewModel.selectedSection == .history)
	}

	private func waitUntil(
		timeout: Duration = .seconds(2),
		condition: @escaping @MainActor () -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while condition() == false {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
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
