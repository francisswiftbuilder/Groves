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

	func didChooseRepository(_ url: URL) {
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
				let savedRepository = try savedRepositoryStore.requestSaveRepository(at: rootURL)
				if tabs.contains(where: { $0.id == savedRepository.id }) == false {
					tabs.append(makeTab(repository: savedRepository))
				}
				didSelectTab(savedRepository.id)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
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

	func didRequestCloseTab(_ id: SavedRepository.ID) {
		guard let closingIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
		do {
			try savedRepositoryStore.requestRemoveRepository(id: id)
			tabs.remove(at: closingIndex)

			if selectedTabID == id {
				let nextIndex = min(closingIndex, tabs.count - 1)
				selectedTabID = nextIndex >= 0 ? tabs[nextIndex].id : nil
				try savedRepositoryStore.requestSelectRepository(id: selectedTabID)
				activateSelectedTabIfNeeded()
				if let selectedTabID {
					sidebarSelection = defaultSidebarSelection(repositoryID: selectedTabID)
				} else {
					sidebarSelection = nil
				}
			}
		} catch {
			alertMessage = error.localizedDescription
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

	private func activateSelectedTabIfNeeded() {
		guard let selectedTab, selectedTab.hasLoadedContent == false else { return }
		selectedTab.hasLoadedContent = true
		selectedTab.workspace.didRequestRefresh()
	}

	private func selectDefaultSidebarItemIfNeeded(repositoryID: RepositoryTab.ID) {
		guard sidebarSelection?.repositoryID != repositoryID else { return }
		sidebarSelection = defaultSidebarSelection(repositoryID: repositoryID)
	}

	private func defaultSidebarSelection(
		repositoryID: RepositoryTab.ID
	) -> RepositorySidebarSelection {
		let section =
			tabs.first(where: { $0.id == repositoryID })?.workspace.selectedSection ?? .changes
		return .section(repositoryID: repositoryID, section: section)
	}
}

enum RepositorySidebarSelection: Hashable {
	case section(repositoryID: RepositoryTab.ID, section: WorkspaceSection)
	case branch(repositoryID: RepositoryTab.ID, id: String)
	case remote(repositoryID: RepositoryTab.ID, id: String)
	case remoteBranch(repositoryID: RepositoryTab.ID, id: String)
	case tag(repositoryID: RepositoryTab.ID, id: String)
	case stash(repositoryID: RepositoryTab.ID, id: String)

	var repositoryID: RepositoryTab.ID {
		switch self {
		case .section(let repositoryID, _),
			.branch(let repositoryID, _),
			.remote(let repositoryID, _),
			.remoteBranch(let repositoryID, _),
			.tag(let repositoryID, _),
			.stash(let repositoryID, _):
			return repositoryID
		}
	}
}
