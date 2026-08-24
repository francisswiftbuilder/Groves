import DomainGitInterface
import Foundation

@MainActor
final class RepositoryTabsViewModel: ObservableObject {
	@Published private(set) var tabs: [RepositoryTab] = []
	@Published private(set) var selectedTabID: SavedRepository.ID?
	@Published var sidebarSelection: RepositorySidebarSelection?
	@Published private(set) var isAddingRepository = false
	@Published var alertMessage: String?

	private let gitRepository: any GitRepository
	private let savedRepositoryStore: any SavedRepositoryStore
	private var addRepositoryTask: Task<Void, Never>?
	private var didRestoreRepositoryWindows = false

	init(
		gitRepository: any GitRepository,
		savedRepositoryStore: any SavedRepositoryStore
	) {
		self.gitRepository = gitRepository
		self.savedRepositoryStore = savedRepositoryStore
		restoreTabs()
	}

	deinit {
		addRepositoryTask?.cancel()
	}

	var selectedTab: RepositoryTab? {
		tabs.first { $0.id == selectedTabID }
	}

	var selectedWorkspace: WorkspaceViewModel? {
		selectedTab?.workspace
	}

	func tab(id: RepositoryTab.ID?) -> RepositoryTab? {
		guard let id else { return nil }
		return tabs.first { $0.id == id }
	}

	func didChooseRepository(
		_ url: URL,
		onOpen: @escaping (RepositoryTab.ID) -> Void = { _ in }
	) {
		addRepositoryTask?.cancel()
		addRepositoryTask = Task {
			isAddingRepository = true
			defer { isAddingRepository = false }

			let didAccessResource = url.startAccessingSecurityScopedResource()
			defer {
				if didAccessResource {
					url.stopAccessingSecurityScopedResource()
				}
			}

			do {
				let rootURL = try await gitRepository.requestRepositoryRoot(at: url)
				try saveAndOpenRepository(at: rootURL, onOpen: onOpen)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func didRequestCloneRepository(
		from remoteURL: String,
		into directoryURL: URL,
		onOpen: @escaping (RepositoryTab.ID) -> Void = { _ in }
	) {
		addRepositoryTask?.cancel()
		addRepositoryTask = Task {
			isAddingRepository = true
			defer { isAddingRepository = false }

			let didAccessResource = directoryURL.startAccessingSecurityScopedResource()
			defer {
				if didAccessResource {
					directoryURL.stopAccessingSecurityScopedResource()
				}
			}

			do {
				let repositoryURL = try await gitRepository.requestCloneRepository(
					from: remoteURL,
					into: directoryURL
				)
				try saveAndOpenRepository(at: repositoryURL, onOpen: onOpen)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func requestWindowRestoration(
		currentRepositoryID: RepositoryTab.ID?
	) -> RepositoryWindowRestoration? {
		guard didRestoreRepositoryWindows == false else { return nil }
		didRestoreRepositoryWindows = true
		let primaryRepositoryID = currentRepositoryID ?? selectedTabID ?? tabs.first?.id
		return RepositoryWindowRestoration(
			primaryRepositoryID: primaryRepositoryID,
			additionalRepositoryIDs: tabs.map(\.id).filter { $0 != primaryRepositoryID }
		)
	}

	func didSelectTab(_ id: SavedRepository.ID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		if selectedTabID != id {
			selectedTabID = id
			do {
				try savedRepositoryStore.requestSelectRepository(id: id)
			} catch {
				alertMessage = error.localizedDescription
			}
		}
		activateSelectedTabIfNeeded()
		selectDefaultSidebarItemIfNeeded(repositoryID: id)
	}

	func didActivateSidebarSelection(_ selection: RepositorySidebarSelection?) {
		guard
			let selection,
			let tab = tabs.first(where: { $0.id == selection.repositoryID })
		else { return }

		didSelectTab(tab.id)
		let workspace = tab.workspace
		switch selection {
		case .section(_, let section):
			workspace.didSelectSection(section)
		case .branch(_, let id):
			guard let branch = workspace.branches.first(where: { $0.id == id }) else { return }
			workspace.didOpenBranch(branch)
		case .remote(_, let id):
			workspace.selectedRemoteID = id
			workspace.didSelectSection(.remotes)
		case .remoteBranch(_, let id):
			guard let branch = workspace.remoteBranches.first(where: { $0.id == id }) else { return }
			workspace.didOpenRemoteBranch(branch)
		case .tag(_, let id):
			guard let tag = workspace.tags.first(where: { $0.id == id }) else { return }
			workspace.didOpenTag(tag)
		case .stash(_, let id):
			workspace.selectedStashID = id
			workspace.didSelectSection(.stashes)
		}
	}

	@discardableResult
	func didRequestCloseTab(_ id: SavedRepository.ID) -> SavedRepository.ID? {
		guard let closingIndex = tabs.firstIndex(where: { $0.id == id }) else { return nil }
		do {
			try savedRepositoryStore.requestRemoveRepository(id: id)
			tabs.remove(at: closingIndex)
			let nextIndex = min(closingIndex, tabs.count - 1)
			let nextRepositoryID = nextIndex >= 0 ? tabs[nextIndex].id : nil

			if selectedTabID == id {
				selectedTabID = nextRepositoryID
				try savedRepositoryStore.requestSelectRepository(id: selectedTabID)
				activateSelectedTabIfNeeded()
				if let selectedTabID {
					sidebarSelection = defaultSidebarSelection(repositoryID: selectedTabID)
				} else {
					sidebarSelection = nil
				}
			}
			return nextRepositoryID
		} catch {
			alertMessage = error.localizedDescription
			return nil
		}
	}

	private func restoreTabs() {
		do {
			let repositories = try savedRepositoryStore.requestRepositories()
			tabs = repositories.map(makeTab)
			selectedTabID = repositories.first(where: \.isSelected)?.id ?? repositories.first?.id
			if repositories.contains(where: \.isSelected) == false {
				try savedRepositoryStore.requestSelectRepository(id: selectedTabID)
			}
			activateSelectedTabIfNeeded()
			if let selectedTabID {
				sidebarSelection = defaultSidebarSelection(repositoryID: selectedTabID)
			}
		} catch {
			alertMessage = error.localizedDescription
		}
	}

	private func makeTab(repository: SavedRepository) -> RepositoryTab {
		RepositoryTab(
			repository: repository,
			workspace: WorkspaceViewModel(
				repository: gitRepository,
				repositoryURL: repository.url
			)
		)
	}

	private func saveAndOpenRepository(
		at repositoryURL: URL,
		onOpen: (RepositoryTab.ID) -> Void
	) throws {
		let savedRepository = try savedRepositoryStore.requestSaveRepository(at: repositoryURL)
		if tabs.contains(where: { $0.id == savedRepository.id }) == false {
			tabs.append(makeTab(repository: savedRepository))
		}
		didSelectTab(savedRepository.id)
		onOpen(savedRepository.id)
	}

	private func activateSelectedTabIfNeeded() {
		guard let selectedTab, selectedTab.hasLoadedContent == false else { return }
		selectedTab.hasLoadedContent = true
		selectedTab.workspace.didRequestRefresh()
	}

	private func selectDefaultSidebarItemIfNeeded(repositoryID: RepositoryTab.ID) {
		guard sidebarSelection?.repositoryID != repositoryID else { return }
		sidebarSelection = defaultSidebarSelection(repositoryID: repositoryID)
	}

	func defaultSidebarSelection(
		repositoryID: RepositoryTab.ID
	) -> RepositorySidebarSelection {
		let section =
			tabs.first(where: { $0.id == repositoryID })?.workspace.selectedSection ?? .changes
		return .section(repositoryID: repositoryID, section: section)
	}
}
