import DomainGitInterface
import Foundation

@MainActor
final class WorkspaceViewModel: ObservableObject {
	struct Actions {
		let resetContent: @MainActor () -> Void
		let distributeSnapshot: @MainActor (RepositorySnapshot, URL?, Bool) -> Void
		let refreshDiffPresentation: @MainActor () -> Void
		let focusConflict: @MainActor (GitConflict) async -> Void
		let activateSidebarSelection: @MainActor (RepositorySidebarSelection) -> Void
	}

	struct Dependencies {
		let contentUseCase: any RepositoryContentUseCase
		let canAutomaticallyRefresh: @MainActor () -> Bool
	}

	@Published private(set) var selectedSection: WorkspaceSection? = .changes
	@Published var expandedSidebarGroups: Set<RepositorySidebarGroup> = []
	@Published private(set) var repositoryURL: URL?
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingContent: Bool
	@Published var alertMessage: String?

	private let dependencies: Dependencies
	private let actions: Actions
	private var refreshTask: Task<Void, Never>?
	private var repositoryMonitorTask: Task<Void, Never>?
	private var monitoredRepositoryURL: URL?
	private var automaticRefreshTask: Task<Void, Never>?
	private var conflictFocusTask: Task<Void, Never>?
	private var contentLoadID: UUID?
	private var hasLoadedContent = false
	private var refreshesWhenMonitoringResumes = false
	private var automaticRefreshRevalidatesSelectedContent = false
	private var isVisible = false
	private var isSceneActive = false

	init(
		dependencies: Dependencies,
		actions: Actions,
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
		repositoryMonitorTask?.cancel()
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
		let changesRepository = repositoryURL != url
		if changesRepository {
			hasLoadedContent = false
		}
		let loadID = beginContentLoad(showsLoadingState: !hasLoadedContent)
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }
			do {
				if changesRepository {
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
		let loadID = beginContentLoad(showsLoadingState: !hasLoadedContent)
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

	func onAppear(isSceneActive: Bool) {
		isVisible = true
		self.isSceneActive = isSceneActive
		updateRepositoryMonitoring()
		resumeContentLoadIfNeeded()
	}

	func onDisappear() {
		isVisible = false
		refreshTask?.cancel()
		refreshTask = nil
		conflictFocusTask?.cancel()
		conflictFocusTask = nil
		contentLoadID = nil
		isLoading = false
		isLoadingContent = false
		updateRepositoryMonitoring()
	}

	func didChangeSceneActivation(_ isActive: Bool) {
		isSceneActive = isActive
		updateRepositoryMonitoring()
		resumeContentLoadIfNeeded()
	}

	func didChangeMonitoredRepository() {
		updateRepositoryMonitoring()
	}

	private func resumeContentLoadIfNeeded() {
		guard isVisible, isSceneActive, !hasLoadedContent, !isLoading else { return }
		didRequestRefresh()
	}

	private func updateRepositoryMonitoring() {
		guard isVisible, isSceneActive else {
			if repositoryMonitorTask != nil {
				refreshesWhenMonitoringResumes = true
			}
			stopRepositoryMonitoring()
			return
		}
		guard let repositoryURL else {
			stopRepositoryMonitoring()
			return
		}
		guard monitoredRepositoryURL != repositoryURL || repositoryMonitorTask == nil else {
			return
		}
		stopRepositoryMonitoring()
		monitoredRepositoryURL = repositoryURL
		repositoryMonitorTask = Task { [weak self] in
			let events = RepositoryFileSystemMonitor.events(at: repositoryURL)
			for await paths in events {
				guard !Task.isCancelled else { return }
				self?.scheduleAutomaticRefresh(
					at: repositoryURL,
					delay: .milliseconds(450),
					revalidatesSelectedContent: self?.containsWorkingTreeEvent(
						paths,
						repositoryURL: repositoryURL
					) == true
				)
			}
		}
		if refreshesWhenMonitoringResumes {
			refreshesWhenMonitoringResumes = false
			scheduleAutomaticRefresh(
				at: repositoryURL,
				delay: .zero,
				revalidatesSelectedContent: true
			)
		}
	}

	private func scheduleAutomaticRefresh(
		at repositoryURL: URL,
		delay: Duration,
		revalidatesSelectedContent: Bool
	) {
		automaticRefreshRevalidatesSelectedContent =
			automaticRefreshRevalidatesSelectedContent || revalidatesSelectedContent
		automaticRefreshTask?.cancel()
		automaticRefreshTask = Task { @MainActor [weak self] in
			do {
				if delay > .zero {
					try await Task.sleep(for: delay)
				}
				guard
					let self,
					!self.isLoading,
					self.dependencies.canAutomaticallyRefresh()
				else { return }
				let revalidatesSelectedContent =
					self.automaticRefreshRevalidatesSelectedContent
				self.automaticRefreshRevalidatesSelectedContent = false
				try await self.requestAllContent(
					at: repositoryURL,
					revalidatesSelectedContent: revalidatesSelectedContent
				)
			} catch is CancellationError {
				return
			} catch {}
		}
	}

	private func containsWorkingTreeEvent(
		_ paths: [String],
		repositoryURL: URL
	) -> Bool {
		let gitDirectoryPath =
			repositoryURL
			.appending(path: ".git", directoryHint: .isDirectory)
			.standardizedFileURL.path

		return paths.contains { path in
			let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
			return standardizedPath != gitDirectoryPath
				&& !standardizedPath.hasPrefix(gitDirectoryPath + "/")
		}
	}

	private func stopRepositoryMonitoring() {
		repositoryMonitorTask?.cancel()
		repositoryMonitorTask = nil
		monitoredRepositoryURL = nil
		automaticRefreshTask?.cancel()
		automaticRefreshTask = nil
		automaticRefreshRevalidatesSelectedContent = false
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

	private func requestAllContent(
		at repositoryURL: URL,
		revalidatesSelectedContent: Bool = true
	) async throws {
		let snapshot = try await contentUseCase.loadSnapshot(at: repositoryURL)
		try apply(
			snapshot,
			at: repositoryURL,
			revalidatesSelectedContent: revalidatesSelectedContent
		)
	}

	private func apply(
		_ snapshot: RepositorySnapshot,
		at repositoryURL: URL?,
		revalidatesSelectedContent: Bool = true
	) throws {
		try Task.checkCancellation()
		guard self.repositoryURL == repositoryURL else { throw CancellationError() }
		actions.distributeSnapshot(snapshot, repositoryURL, revalidatesSelectedContent)
		hasLoadedContent = true
	}

	private func beginContentLoad(showsLoadingState: Bool) -> UUID {
		let id = UUID()
		contentLoadID = id
		isLoading = true
		if showsLoadingState {
			isLoadingContent = true
		}
		return id
	}

	private func finishContentLoad(id: UUID) {
		guard contentLoadID == id else { return }
		contentLoadID = nil
		isLoading = false
		isLoadingContent = false
	}
}
