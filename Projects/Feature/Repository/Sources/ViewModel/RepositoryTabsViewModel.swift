import DomainGitInterface
import Foundation

@MainActor
final class RepositoryTabsViewModel: ObservableObject {
	@Published private(set) var tabs: [RepositoryTab] = []
	@Published private(set) var selectedTabID: SavedRepository.ID?
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
		selectedTabID = id
		do {
			try savedRepositoryStore.requestSelectRepository(id: id)
			activateSelectedTabIfNeeded()
		} catch {
			alertMessage = error.localizedDescription
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
}
