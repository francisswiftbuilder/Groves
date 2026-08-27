import DomainGitInterface
import Foundation

@MainActor
final class RepositoryTabsViewModel: ObservableObject {
	@Published private(set) var tabs: [RepositoryTab] = []
	@Published private(set) var selectedTabID: SavedRepository.ID?
	@Published private(set) var isAddingRepository = false
	@Published var alertMessage: String?

	private let useCase: any RepositoryTabsUseCase
	private let makeWorkspace: @MainActor (URL) -> RepositoryWorkspace
	private var addRepositoryTask: Task<Void, Never>?
	private var didRestoreRepositoryWindows = false

	init(
		useCase: any RepositoryTabsUseCase,
		makeWorkspace: @escaping @MainActor (URL) -> RepositoryWorkspace
	) {
		self.useCase = useCase
		self.makeWorkspace = makeWorkspace
		restoreTabs()
	}

	deinit {
		addRepositoryTask?.cancel()
	}

	var selectedTab: RepositoryTab? {
		tabs.first { $0.id == selectedTabID }
	}

	var selectedWorkspace: WorkspaceViewModel? {
		selectedTab?.workspace.viewModel
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

			do {
				let repository = try await useCase.openRepository(at: url)
				openRepository(repository, onOpen: onOpen)
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

			do {
				let repository = try await useCase.cloneRepository(
					from: remoteURL,
					into: directoryURL
				)
				openRepository(repository, onOpen: onOpen)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func didRequestCancelAddingRepository() {
		addRepositoryTask?.cancel()
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
				try useCase.selectRepository(id: id)
			} catch {
				alertMessage = error.localizedDescription
			}
		}
		activateSelectedTabIfNeeded()
	}

	func didActivateSidebarSelection(_ selection: RepositorySidebarSelection?) {
		guard
			let selection,
			let tab = tabs.first(where: { $0.id == selection.repositoryID })
		else { return }

		didSelectTab(tab.id)
		tab.workspace.viewModel.didActivateSidebarSelection(selection)
	}

	@discardableResult
	func didRequestCloseTab(_ id: SavedRepository.ID) -> SavedRepository.ID? {
		guard tabs.contains(where: { $0.id == id }) else { return nil }
		do {
			let snapshot = try useCase.removeRepository(id: id)
			reconcileTabs(with: snapshot.repositories)
			selectedTabID = snapshot.selectedRepositoryID
			activateSelectedTabIfNeeded()
			return snapshot.selectedRepositoryID
		} catch {
			alertMessage = error.localizedDescription
			return nil
		}
	}

	private func restoreTabs() {
		do {
			let snapshot = try useCase.loadTabs()
			tabs = snapshot.repositories.map(makeTab)
			selectedTabID = snapshot.selectedRepositoryID
			activateSelectedTabIfNeeded()
		} catch {
			alertMessage = error.localizedDescription
		}
	}

	private func makeTab(repository: SavedRepository) -> RepositoryTab {
		RepositoryTab(
			repository: repository,
			workspace: makeWorkspace(repository.url)
		)
	}

	private func openRepository(
		_ repository: SavedRepository,
		onOpen: (RepositoryTab.ID) -> Void
	) {
		if tabs.contains(where: { $0.id == repository.id }) == false {
			tabs.append(makeTab(repository: repository))
		}
		selectedTabID = repository.id
		activateSelectedTabIfNeeded()
		onOpen(repository.id)
	}

	private func reconcileTabs(with repositories: [SavedRepository]) {
		let existingTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		tabs = repositories.map { repository in
			existingTabs[repository.id] ?? makeTab(repository: repository)
		}
	}

	private func activateSelectedTabIfNeeded() {
		guard let selectedTab, selectedTab.hasLoadedContent == false else { return }
		selectedTab.hasLoadedContent = true
		selectedTab.workspace.viewModel.didRequestRefresh()
	}

	func defaultSidebarSelection(
		repositoryID: RepositoryTab.ID
	) -> RepositorySidebarSelection {
		let section =
			tabs.first(where: { $0.id == repositoryID })?.workspace.viewModel.selectedSection
			?? .changes
		return .section(repositoryID: repositoryID, section: section)
	}
}
