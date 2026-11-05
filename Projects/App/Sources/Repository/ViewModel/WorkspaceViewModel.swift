import DomainGitInterface
import Foundation
import OSLog
import Observation

@MainActor
@Observable
final class WorkspaceViewModel {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "io.github.francisswiftbuilder.Groves",
		category: "RepositoryRefresh")

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
		let fileSystemEvents: @Sendable (URL) -> AsyncStream<[String]>

		init(
			contentUseCase: any RepositoryContentUseCase,
			canAutomaticallyRefresh: @escaping @MainActor () -> Bool,
			fileSystemEvents: @escaping @Sendable (URL) -> AsyncStream<[String]> = {
				RepositoryFileSystemMonitor.events(at: $0)
			}
		) {
			self.contentUseCase = contentUseCase
			self.canAutomaticallyRefresh = canAutomaticallyRefresh
			self.fileSystemEvents = fileSystemEvents
		}
	}

	private(set) var selectedSection: WorkspaceSection? = .changes
	var expandedSidebarGroups: Set<RepositorySidebarGroup> = []
	private(set) var repositoryURL: URL?
	private(set) var isLoading = false
	private(set) var isLoadingContent: Bool
	var alertMessage: String?

	private let dependencies: Dependencies
	private let actions: Actions
	@ObservationIgnored private var refreshTask: Task<Void, Never>?
	@ObservationIgnored private var repositoryMonitorTask: Task<Void, Never>?
	private var monitoredRepositoryURL: URL?
	private var monitoredGitDirectoryPaths: [String] = []
	@ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
	@ObservationIgnored private var conflictFocusTask: Task<Void, Never>?
	private var contentLoadID: UUID?
	private var snapshotRevision = 0
	private var hasLoadedContent = false
	private var refreshesWhenMonitoringResumes = false
	private var automaticRefreshRevalidatesSelectedContent = false
	private var needsAutomaticRefresh = false
	private var automaticRefreshRequestID: UUID?
	private var isVisible = false
	private var isSceneActive = false
	private var preparedSidebarRepositoryID: RepositoryTab.ID?

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
		guard preparedSidebarRepositoryID != repositoryID else { return }
		preparedSidebarRepositoryID = repositoryID
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

	func didChooseRepository(_ url: URL, preservesContent: Bool = false) {
		refreshTask?.cancel()
		let changesRepository = repositoryURL != url
		if changesRepository {
			hasLoadedContent = false
		}
		let loadID = beginContentLoad(showsLoadingState: !hasLoadedContent)
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }
			do {
				if changesRepository, !preservesContent {
					actions.resetContent()
					expandedSidebarGroups = []
					preparedSidebarRepositoryID = nil
				}
				repositoryURL = url
				try await requestAllContent(
					at: url,
					revalidatesSelectedContent: changesRepository && preservesContent
				)
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
			if hasLoadedContent {
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
		monitoredGitDirectoryPaths = RepositoryFileSystemMonitor.gitDirectories(at: repositoryURL).map(
			\.path)
		let fileSystemEvents = dependencies.fileSystemEvents
		repositoryMonitorTask = Task { [weak self] in
			var reconnects = false
			var reconnectDelay = Duration.seconds(1)
			do {
				while !Task.isCancelled {
					let events = fileSystemEvents(repositoryURL)
					if reconnects {
						self?.monitoredGitDirectoryPaths = RepositoryFileSystemMonitor.gitDirectories(
							at: repositoryURL
						).map(\.path)
						self?.scheduleAutomaticRefresh(
							at: repositoryURL, delay: .zero, revalidatesSelectedContent: true)
					}
					for await paths in events {
						guard !Task.isCancelled else { return }
						reconnectDelay = .seconds(1)
						self?.scheduleAutomaticRefresh(
							at: repositoryURL, delay: .milliseconds(450),
							revalidatesSelectedContent: self?.containsWorkingTreeEvent(
								paths, repositoryURL: repositoryURL) == true)
					}
					try Task.checkCancellation()
					if !reconnects {
						Self.logger.warning("Repository file monitoring ended; reconnecting")
					}
					reconnects = true
					try await Task.sleep(for: reconnectDelay)
					reconnectDelay = min(reconnectDelay * 2, .seconds(30))
				}
			} catch {}
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
		guard monitoredRepositoryURL == repositoryURL, isVisible, isSceneActive else { return }
		needsAutomaticRefresh = true
		automaticRefreshRevalidatesSelectedContent =
			automaticRefreshRevalidatesSelectedContent || revalidatesSelectedContent
		guard automaticRefreshTask == nil else { return }
		let requestID = UUID()
		automaticRefreshRequestID = requestID
		automaticRefreshTask = Task { @MainActor [weak self] in
			defer { self?.finishAutomaticRefresh(id: requestID) }
			do {
				var nextDelay = delay
				var failureCount = 0
				while !Task.isCancelled {
					if nextDelay > .zero {
						try await Task.sleep(for: nextDelay)
					}
					guard let self, monitoredRepositoryURL == repositoryURL,
						self.repositoryURL == repositoryURL
					else { return }
					guard !isLoading, dependencies.canAutomaticallyRefresh() else {
						nextDelay = .milliseconds(100)
						continue
					}
					guard needsAutomaticRefresh else { return }
					let revalidatesSelectedContent = automaticRefreshRevalidatesSelectedContent
					needsAutomaticRefresh = false
					automaticRefreshRevalidatesSelectedContent = false
					do {
						let revision = snapshotRevision
						let snapshot = try await contentUseCase.loadSnapshot(at: repositoryURL)
						try Task.checkCancellation()
						if revision == snapshotRevision, !isLoading, dependencies.canAutomaticallyRefresh() {
							try apply(
								snapshot, at: repositoryURL, revalidatesSelectedContent: revalidatesSelectedContent)
						} else {
							needsAutomaticRefresh = true
							automaticRefreshRevalidatesSelectedContent =
								automaticRefreshRevalidatesSelectedContent || revalidatesSelectedContent
						}
						failureCount = 0
					} catch {
						try Task.checkCancellation()
						needsAutomaticRefresh = true
						automaticRefreshRevalidatesSelectedContent =
							automaticRefreshRevalidatesSelectedContent || revalidatesSelectedContent
						failureCount += 1
						guard failureCount < 3 else {
							Self.logger.error(
								"Automatic repository refresh failed after retries: \(error.localizedDescription, privacy: .private)"
							)
							return
						}
					}
					guard needsAutomaticRefresh else { return }
					nextDelay = .milliseconds(450)
				}
			} catch {}
		}
	}

	private func finishAutomaticRefresh(id: UUID) {
		guard automaticRefreshRequestID == id else { return }
		automaticRefreshRequestID = nil
		automaticRefreshTask = nil
	}

	private func containsWorkingTreeEvent(
		_ paths: [String],
		repositoryURL: URL
	) -> Bool {
		let gitDirectoryPaths =
			monitoredGitDirectoryPaths
			+ [repositoryURL.appending(path: ".git").standardizedFileURL.path]

		return paths.contains { path in
			let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
			if gitDirectoryPaths.contains(where: { gitDirectoryPath in
				["index", "HEAD", "packed-refs", "refs", "refs/heads"].contains(where: {
					standardizedPath == gitDirectoryPath + "/" + $0
				}) || standardizedPath.hasPrefix(gitDirectoryPath + "/refs/heads/")
			}) {
				return true
			}
			return !gitDirectoryPaths.contains {
				standardizedPath == $0 || standardizedPath.hasPrefix($0 + "/")
			}
		}
	}

	private func stopRepositoryMonitoring() {
		repositoryMonitorTask?.cancel()
		repositoryMonitorTask = nil
		monitoredRepositoryURL = nil
		monitoredGitDirectoryPaths = []
		automaticRefreshTask?.cancel()
		automaticRefreshTask = nil
		automaticRefreshRequestID = nil
		needsAutomaticRefresh = false
		automaticRefreshRevalidatesSelectedContent = false
	}

	func didChangeDiffOptions() {
		actions.refreshDiffPresentation()
	}

	func didApplyDiffMutation() {
		snapshotRevision += 1
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
		let revision = snapshotRevision
		let snapshot = try await contentUseCase.loadSnapshot(at: repositoryURL)
		try Task.checkCancellation()
		guard revision == snapshotRevision else {
			scheduleAutomaticRefresh(
				at: repositoryURL, delay: .zero, revalidatesSelectedContent: revalidatesSelectedContent)
			return
		}
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
		snapshotRevision += 1
		actions.distributeSnapshot(snapshot, repositoryURL, revalidatesSelectedContent)
		hasLoadedContent = true
	}

	private func beginContentLoad(showsLoadingState: Bool) -> UUID {
		snapshotRevision += 1
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
