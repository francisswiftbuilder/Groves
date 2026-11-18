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
	func aSupersededCloneCannotClearLoadingOrPersistItsRepository() async throws {
		let gate = GitDiffGate(suspendsRequests: true)
		let store = SavedRepositoryStoreSpy(repositories: [])
		let viewModel = makeRepositoryTabsViewModel(
			repository: GitRepositoryStub(cloneGate: gate), savedRepositoryStore: store)
		let oldURL = URL(fileURLWithPath: "/tmp/Old", isDirectory: true)
		let currentURL = URL(fileURLWithPath: "/tmp/Current", isDirectory: true)
		var opened: [UUID] = []
		let old = viewModel.didRequestCloneRepository(
			from: "https://github.com/owner/Old.git", into: oldURL,
			actions: .init { opened.append($0) })
		try await waitUntil { await gate.totalCallCount() == 1 }
		let current = viewModel.didRequestCloneRepository(
			from: "https://github.com/owner/Current.git", into: currentURL,
			actions: .init { opened.append($0) })
		try await waitUntil { await gate.totalCallCount() == 2 }

		await gate.resumeCall(0)
		await old.value

		#expect(viewModel.isAddingRepository)
		#expect(viewModel.alertMessage == nil)
		#expect(viewModel.tabs.isEmpty)
		#expect(opened.isEmpty)
		#expect(try store.requestRepositories().isEmpty)

		await gate.resumeCall(1)
		await current.value

		let tab = try #require(viewModel.tabs.first)
		#expect(!viewModel.isAddingRepository)
		#expect(viewModel.alertMessage == nil)
		#expect(viewModel.tabs.count == 1)
		#expect(
			tab.repository.url == currentURL.appending(path: "Repository", directoryHint: .isDirectory))
		#expect(opened == [tab.id])
		#expect(try store.requestRepositories().map(\.id) == [tab.id])
		#expect(store.selectedRepositoryID == tab.id)
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

		viewModel.didPresentCloneDestinationImporter(
			remoteURL: "  https://github.com/owner/Groves.git  ")

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
		viewModel.didPresentCloneDestinationImporter(remoteURL: "https://github.com/owner/Groves.git")

		#expect(viewModel.isFolderImporterPresented)
		#expect(viewModel.folderImportRequest?.allowsMultipleSelection == false)
	}

	@Test(arguments: [
		("https://gitlab.com/example/project.git", "https://gitlab.com/example/project.git"),
		("https://codeberg.org/example/project", "https://codeberg.org/example/project"),
		("git@github.com:example/project.git", "https://github.com/example/project.git"),
		("ssh://git@github.com/example/project.git", "ssh://git@github.com/example/project.git"),
	])
	func cloneSearchAcceptsSupportedRemoteURLs(input: String, expected: String) throws {
		let viewModel = RepositoryWindowViewModel()
		viewModel.didPresentCloneDestinationImporter(remoteURL: input)

		let request = try #require(viewModel.consumeFolderImportRequest())
		guard case .clone(let remoteURL) = request else {
			Issue.record("Expected a clone folder import request")
			return
		}
		#expect(remoteURL == expected)
		#expect(!request.allowsMultipleSelection)
	}

	@Test(arguments: [
		"example/project", "https://gitlab.com", "https://", "https://user:secret@gitlab.com/a/b",
		"https://gitlab.com/a/b?token=secret", "file:///tmp/repo", "http://gitlab.com/a/b",
	])
	func cloneSearchDoesNotTreatSearchTermsOrUnsupportedInputsAsCloneURLs(input: String) {
		let viewModel = RepositoryWindowViewModel()
		viewModel.didPresentCloneDestinationImporter(remoteURL: input)
		#expect(viewModel.folderImportRequest == nil)
		#expect(!viewModel.isFolderImporterPresented)
	}

	@Test
	func testRemovingSelectedRepositorySelectsNeighborAndPersistsSelection() {
		let first = makeSavedRepository(name: "First", position: 0, isSelected: true)
		let second = makeSavedRepository(name: "Second", position: 1, isSelected: false)
		let store = SavedRepositoryStoreSpy(repositories: [first, second])
		let viewModel = makeRepositoryTabsViewModel(savedRepositoryStore: store)

		viewModel.didRequestRemoveRepository(first.id)

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

		viewModel.didRequestRemoveRepository(repository.id)

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
		condition: @escaping @MainActor () async -> Bool
	) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: timeout)
		while await condition() == false {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for condition")
				throw CancellationError()
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
