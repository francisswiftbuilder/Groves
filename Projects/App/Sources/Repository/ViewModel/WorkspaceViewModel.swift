import DomainGitInterface
import Foundation

@MainActor
final class WorkspaceViewModel: ObservableObject {
	@Published private(set) var selectedSection: WorkspaceSection? = .changes
	@Published var expandedSidebarGroups: Set<RepositorySidebarGroup> = []
	@Published private(set) var repositoryURL: URL?
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingContent: Bool
	@Published var alertMessage: String?

	private let dependencies: WorkspaceViewModelDependencies
	private let actions: WorkspaceViewModelActions
	private var refreshTask: Task<Void, Never>?
	private var automaticRefreshTask: Task<Void, Never>?
	private var conflictFocusTask: Task<Void, Never>?
	private var contentLoadID: UUID?

	init(
		dependencies: WorkspaceViewModelDependencies,
		actions: WorkspaceViewModelActions,
		repositoryURL: URL? = nil
	) {
		self.dependencies = dependencies
		self.actions = actions
		self.repositoryURL = repositoryURL
		isLoadingContent = repositoryURL != nil
	}

	private var contentUseCase: any RepositoryContentUseCase {
		dependencies.contentUseCase
	}

	deinit {
		refreshTask?.cancel()
		automaticRefreshTask?.cancel()
		conflictFocusTask?.cancel()
	}

	var repositoryName: String {
		repositoryURL?.lastPathComponent ?? "No Repository"
	}

	func didSelectSection(_ section: WorkspaceSection) {
		selectedSection = section
	}

	func didActivateSidebarSelection(_ selection: RepositorySidebarSelection) {
		switch selection {
		case .section(_, let section):
			selectedSection = section
		case .branch, .remoteBranch, .tag:
			break
		case .remote:
			selectedSection = .remotes
		case .stash:
			selectedSection = .stashes
		}
		actions.activateSidebarSelection(selection)
	}

	func didPrepareSidebar(repositoryID: RepositoryTab.ID) {
		var groups = expandedSidebarGroups
		groups.formUnion(
			RepositorySidebarGroupKind.allCases.map {
				RepositorySidebarGroup(repositoryID: repositoryID, kind: $0)
			}
		)
		if let selectedSection, let kind = RepositorySidebarGroupKind(section: selectedSection) {
			groups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
		}
		if groups != expandedSidebarGroups {
			expandedSidebarGroups = groups
		}
	}

	func setSidebarGroup(_ group: RepositorySidebarGroup, isExpanded: Bool) {
		if isExpanded {
			expandedSidebarGroups.insert(group)
		} else {
			expandedSidebarGroups.remove(group)
		}
	}

	func didChooseRepository(_ url: URL) {
		refreshTask?.cancel()
		let loadID = beginContentLoad()
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }
			do {
				if repositoryURL != url {
					actions.resetContent()
					expandedSidebarGroups = []
				}
				repositoryURL = url
				try await requestAllContent(at: url)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func didRequestRefresh() {
		guard let repositoryURL else { return }
		refreshTask?.cancel()
		let loadID = beginContentLoad()
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }
			do {
				try await requestAllContent(at: repositoryURL)
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func monitorRepositoryChanges() async {
		guard let repositoryURL else { return }
		let events = RepositoryFileSystemMonitor.events(at: repositoryURL)
		defer {
			automaticRefreshTask?.cancel()
			automaticRefreshTask = nil
		}

		for await _ in events {
			guard !Task.isCancelled else { return }
			automaticRefreshTask?.cancel()
			automaticRefreshTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: .milliseconds(450))
					guard
						let self,
						!self.isLoading,
						self.dependencies.canAutomaticallyRefresh()
					else { return }
					try await self.requestAllContent(at: repositoryURL)
				} catch is CancellationError {
					return
				} catch {}
			}
		}
	}

	func didChangeDiffOptions() {
		actions.refreshDiffPresentation()
	}

	func didViewConflict(_ conflict: GitConflict) {
		selectedSection = .changes
		conflictFocusTask?.cancel()
		conflictFocusTask = Task {
			await actions.focusConflict(conflict)
		}
	}

	func didProduceSnapshot(_ snapshot: RepositorySnapshot) {
		do {
			try apply(snapshot, at: repositoryURL)
		} catch is CancellationError {
			return
		} catch {
			alertMessage = error.localizedDescription
		}
	}

	private func requestAllContent(at repositoryURL: URL) async throws {
		let snapshot = try await contentUseCase.loadSnapshot(at: repositoryURL)
		try apply(snapshot, at: repositoryURL)
	}

	private func apply(_ snapshot: RepositorySnapshot, at repositoryURL: URL?) throws {
		try Task.checkCancellation()
		guard self.repositoryURL == repositoryURL else { throw CancellationError() }
		actions.distributeSnapshot(snapshot, repositoryURL)
	}

	private func beginContentLoad() -> UUID {
		let id = UUID()
		contentLoadID = id
		isLoading = true
		isLoadingContent = true
		return id
	}

	private func finishContentLoad(id: UUID) {
		guard contentLoadID == id else { return }
		contentLoadID = nil
		isLoading = false
		isLoadingContent = false
	}
}
