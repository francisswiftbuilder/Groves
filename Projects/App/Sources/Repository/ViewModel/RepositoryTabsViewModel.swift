import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
final class RepositoryTabsViewModel {
	struct Actions {
		let didOpenRepository: @MainActor (RepositoryTab.ID) -> Void
	}

	struct Dependencies {
		let useCase: any RepositoryTabsUseCase
		let makeWorkspace: @MainActor (URL) -> RepositoryWorkspace
	}

	private(set) var tabs: [RepositoryTab] = []
	private(set) var selectedTabID: SavedRepository.ID?
	private(set) var isAddingRepository = false
	var alertMessage: String?

	private let dependencies: Dependencies
	@ObservationIgnored private var addRepositoryTask: Task<Void, Never>?
	private var didRestoreRepositoryWindows = false

	init(dependencies: Dependencies) {
		self.dependencies = dependencies
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
		actions: Actions
	) {
		didChooseRepositories([url], actions: actions)
	}

	func didChooseRepositories(
		_ urls: [URL],
		actions: Actions
	) {
		guard !urls.isEmpty else { return }
		addRepositoryTask?.cancel()
		addRepositoryTask = Task {
			isAddingRepository = true
			defer { isAddingRepository = false }

			var failures: [String] = []
			for url in urls {
				do {
					try Task.checkCancellation()
					let repository = try await dependencies.useCase.openRepository(at: url)
					try Task.checkCancellation()
					openRepository(repository, actions: actions)
				} catch is CancellationError {
					return
				} catch {
					failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
				}
			}

			if !failures.isEmpty {
				alertMessage = failures.joined(separator: "\n")
			}
		}
	}

	func didRequestCloneRepository(
		from remoteURL: String,
		into directoryURL: URL,
		actions: Actions
	) {
		addRepositoryTask?.cancel()
		addRepositoryTask = Task {
			isAddingRepository = true
			defer { isAddingRepository = false }

			do {
				let repository = try await dependencies.useCase.cloneRepository(
					from: remoteURL,
					into: directoryURL
				)
				try Task.checkCancellation()
				openRepository(repository, actions: actions)
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
		let primaryRepositoryID = tab(id: currentRepositoryID)?.id ?? selectedTabID ?? tabs.first?.id
		return RepositoryWindowRestoration(
			primaryRepositoryID: primaryRepositoryID,
			additionalRepositoryIDs: tabs.map(\.id).filter { $0 != primaryRepositoryID }
		)
	}

	func didSelectTab(_ id: SavedRepository.ID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		if selectedTabID != id {
			do {
				try dependencies.useCase.selectRepository(id: id)
				selectedTabID = id
			} catch {
				alertMessage = error.localizedDescription
			}
		}
		didPrepareTab(id)
	}

	func didPrepareTab(_ id: SavedRepository.ID) {
		guard let tab = tab(id: id), tab.hasLoadedContent == false else { return }
		tab.hasLoadedContent = true
		tab.workspace.viewModel.didRequestRefresh()
	}

	func didActivateSidebarSelection(_ selection: RepositorySidebarSelection?) {
		guard
			let selection,
			let tab = tabs.first(where: { $0.id == selection.repositoryID })
		else { return }

		didPrepareTab(tab.id)
		tab.workspace.viewModel.didActivateSidebarSelection(selection)
	}

	@discardableResult
	func didRequestCloseTab(_ id: SavedRepository.ID) -> SavedRepository.ID? {
		guard tabs.contains(where: { $0.id == id }) else { return nil }
		do {
			let snapshot = try dependencies.useCase.removeRepository(id: id)
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
			let snapshot = try dependencies.useCase.loadTabs()
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
			workspace: dependencies.makeWorkspace(repository.url)
		)
	}

	private func openRepository(
		_ repository: SavedRepository,
		actions: Actions
	) {
		if let index = tabs.firstIndex(where: { $0.id == repository.id }) {
			tabs[index] = updateTab(tabs[index], with: repository)
		} else {
			tabs.append(makeTab(repository: repository))
		}
		selectedTabID = repository.id
		activateSelectedTabIfNeeded()
		actions.didOpenRepository(repository.id)
	}

	private func reconcileTabs(with repositories: [SavedRepository]) {
		let existingTabs = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
		tabs = repositories.map { repository in
			if let tab = existingTabs[repository.id] {
				return updateTab(tab, with: repository)
			}
			return makeTab(repository: repository)
		}
	}

	private func updateTab(_ tab: RepositoryTab, with repository: SavedRepository) -> RepositoryTab {
		guard tab.repository != repository else { return tab }
		let changesLocation = tab.repository.url != repository.url
		if changesLocation {
			tab.workspace.viewModel.didChooseRepository(repository.url, preservesContent: true)
		}
		let updatedTab = RepositoryTab(repository: repository, workspace: tab.workspace)
		updatedTab.hasLoadedContent = tab.hasLoadedContent || changesLocation
		return updatedTab
	}

	private func activateSelectedTabIfNeeded() {
		guard let selectedTabID else { return }
		didPrepareTab(selectedTabID)
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
