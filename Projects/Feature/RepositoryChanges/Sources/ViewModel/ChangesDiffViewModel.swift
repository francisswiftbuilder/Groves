import Combine
import CoreRepositoryDiff
import DomainGitInterface
import Foundation

@MainActor
public final class ChangesDiffViewModel: ObservableObject {
	public struct Actions {
		public let didApplyMutation:
			@MainActor ([WorkingTreeChange], WorkingTreeChange, GitDiffSource) -> Void
		public let didReceiveError: @MainActor (String) -> Void

		public init(
			didApplyMutation:
				@escaping @MainActor (
					[WorkingTreeChange], WorkingTreeChange, GitDiffSource
				) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void
		) {
			self.didApplyMutation = didApplyMutation
			self.didReceiveError = didReceiveError
		}
	}

	public struct Dependencies {
		public let changesUseCase: any RepositoryChangesUseCase
		public let preferences: WorkspaceDiffPreferences
		public let repositoryURL: @MainActor () -> URL?

		public init(
			changesUseCase: any RepositoryChangesUseCase,
			preferences: WorkspaceDiffPreferences,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.changesUseCase = changesUseCase
			self.preferences = preferences
			self.repositoryURL = repositoryURL
		}
	}

	@Published private(set) var diff = ""
	@Published private(set) var imageDiff: GitImageDiff?
	@Published public private(set) var isLoading = false
	@Published public private(set) var isApplyingAction = false
	@Published var pendingConfirmation: ChangesDiffConfirmation?

	var preferences: WorkspaceDiffPreferences {
		dependencies.preferences
	}

	private let dependencies: Dependencies
	private let actions: Actions
	private var selection: ChangesDiffSelection?
	private var displayedSelection: WorkspaceChangeSelection?
	private var activeLoadRequestID: Int?
	private var loadRequestSequence = 0
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0
	private var loadTask: Task<Void, Never>?
	private var mutationTask: Task<Void, Never>?

	public init(
		dependencies: Dependencies,
		actions: Actions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		loadTask?.cancel()
		mutationTask?.cancel()
	}

	var selectedDiffLineAction: GitDiffLineAction? {
		guard !preferences.options.ignoresWhitespace else { return nil }
		guard
			case .workingTree(_, let change, let source) = selection
		else { return nil }
		if source == .unstaged, change.workingTreeState == .modified {
			return .stage
		}
		if source == .staged, change.indexState == .modified {
			return .unstage
		}
		return nil
	}

	var selectedDiffHunkActions: [GitDiffHunkAction] {
		guard !preferences.options.ignoresWhitespace else { return [] }
		switch selectedDiffLineAction {
		case .stage:
			return selection?.workingTreeChange?.workingTreeState == .modified
				? [.stage, .discard]
				: [.stage]
		case .unstage:
			return [.unstage]
		case .none:
			return []
		}
	}

	public func didSelect(_ selection: ChangesDiffSelection?, forceReload: Bool = false) {
		let previousSelection = self.selection
		self.selection = selection
		guard forceReload || previousSelection != selection else { return }
		loadTask?.cancel()
		clearLoad()

		guard let selection, let repositoryURL = dependencies.repositoryURL() else {
			clearDisplayedDiff()
			return
		}
		let shouldShowLoading = displayedSelection != selection.identifier
		if shouldShowLoading {
			clearDisplayedDiff()
		}
		requestDiff(for: selection, at: repositoryURL)
	}

	public func didChangeDiffOptions() {
		didSelect(selection, forceReload: true)
	}

	public func reset() {
		cancelTasks()
		selection = nil
		pendingConfirmation = nil
		clearDisplayedDiff()
	}

	func cancelTasks() {
		loadTask?.cancel()
		mutationTask?.cancel()
		loadTask = nil
		mutationTask = nil
		activeLoadRequestID = nil
		activeMutationRequestID = nil
		isLoading = false
		isApplyingAction = false
	}

	func didRequestApplyDiffLine(
		_ lineSelection: GitDiffLineSelection,
		action: GitDiffLineAction
	) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			case .workingTree(_, let change, let source) = selection,
			selectedDiffLineAction == action,
			!isLoading,
			!isApplyingAction
		else { return }
		requestMutation(replacing: change, source: source) {
			try await self.dependencies.changesUseCase.applyDiffLine(
				lineSelection,
				action: action,
				for: change,
				at: repositoryURL
			)
		}
	}

	func didRequestApplyDiffHunk(
		_ hunkSelection: GitDiffHunkSelection,
		action: GitDiffHunkAction
	) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			case .workingTree(_, let change, let source) = selection,
			selectedDiffHunkActions.contains(action),
			!isLoading,
			!isApplyingAction
		else { return }
		if action == .discard {
			pendingConfirmation = ChangesDiffConfirmation(
				selection: hunkSelection,
				change: change,
				options: preferences.options
			)
			return
		}
		requestMutation(replacing: change, source: source) {
			try await self.dependencies.changesUseCase.applyDiffHunk(
				hunkSelection,
				action: action,
				for: change,
				options: self.preferences.options,
				at: repositoryURL
			)
		}
	}

	func didConfirmPendingConfirmation() {
		guard
			let confirmation = pendingConfirmation,
			let repositoryURL = dependencies.repositoryURL(),
			case .workingTree(_, let selectedChange, let source) = selection,
			selectedChange == confirmation.change,
			!isLoading,
			!isApplyingAction
		else {
			pendingConfirmation = nil
			return
		}
		pendingConfirmation = nil
		requestMutation(replacing: confirmation.change, source: source) {
			try await self.dependencies.changesUseCase.applyDiffHunk(
				confirmation.selection,
				action: .discard,
				for: confirmation.change,
				options: confirmation.options,
				at: repositoryURL
			)
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	private func requestDiff(
		for selection: ChangesDiffSelection,
		at repositoryURL: URL
	) {
		loadRequestSequence += 1
		let requestID = loadRequestSequence
		activeLoadRequestID = requestID
		isLoading = true
		loadTask = Task {
			defer { finishLoad(for: requestID) }
			do {
				switch selection {
				case .workingTree(_, let change, let source):
					try await loadDiff(
						for: change,
						source: source,
						selection: selection,
						requestID: requestID,
						at: repositoryURL
					)
				case .amend(_, let change):
					try await loadDiff(
						for: change,
						selection: selection,
						requestID: requestID,
						at: repositoryURL
					)
				}
			} catch is CancellationError {
				return
			} catch {
				guard activeLoadRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
			}
		}
	}

	private func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		selection: ChangesDiffSelection,
		requestID: Int,
		at repositoryURL: URL
	) async throws {
		if DiffImageFileSupport.isSupported(path: change.path) {
			let imageDiff = try await dependencies.changesUseCase.loadImageDiff(
				for: change,
				source: source,
				at: repositoryURL
			)
			updateDisplayedImageDiff(imageDiff, for: selection, requestID: requestID)
		} else {
			let diff = try await dependencies.changesUseCase.loadDiff(
				for: change,
				source: source,
				options: preferences.options,
				at: repositoryURL
			)
			updateDisplayedDiff(diff, for: selection, requestID: requestID)
		}
	}

	private func loadDiff(
		for change: GitAmendChange,
		selection: ChangesDiffSelection,
		requestID: Int,
		at repositoryURL: URL
	) async throws {
		if DiffImageFileSupport.isSupported(path: change.path) {
			let imageDiff = try await dependencies.changesUseCase.loadAmendImageDiff(
				for: change,
				at: repositoryURL
			)
			updateDisplayedImageDiff(imageDiff, for: selection, requestID: requestID)
		} else {
			let diff = try await dependencies.changesUseCase.loadAmendDiff(
				for: change,
				options: preferences.options,
				at: repositoryURL
			)
			updateDisplayedDiff(diff, for: selection, requestID: requestID)
		}
	}

	private func requestMutation(
		replacing change: WorkingTreeChange,
		source: GitDiffSource,
		_ operation: @escaping @MainActor () async throws -> [WorkingTreeChange]
	) {
		mutationTask?.cancel()
		loadTask?.cancel()
		clearLoad()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				let refreshedChanges = try await operation()
				guard let self, self.activeMutationRequestID == requestID else { return }
				actions.didApplyMutation(refreshedChanges, change, source)
			} catch is CancellationError {
				return
			} catch {
				guard let self, self.activeMutationRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
			}
		}
	}

	private func beginMutation() -> Int {
		mutationRequestSequence += 1
		activeMutationRequestID = mutationRequestSequence
		isApplyingAction = true
		return mutationRequestSequence
	}

	private func finishMutation(id: Int) {
		guard activeMutationRequestID == id else { return }
		activeMutationRequestID = nil
		mutationTask = nil
		isApplyingAction = false
	}

	private func updateDisplayedDiff(
		_ requestedDiff: String,
		for selection: ChangesDiffSelection,
		requestID: Int
	) {
		guard activeLoadRequestID == requestID, self.selection == selection else { return }
		if diff != requestedDiff {
			diff = requestedDiff
		}
		if imageDiff != nil {
			imageDiff = nil
		}
		displayedSelection = selection.identifier
	}

	private func updateDisplayedImageDiff(
		_ requestedImageDiff: GitImageDiff,
		for selection: ChangesDiffSelection,
		requestID: Int
	) {
		guard activeLoadRequestID == requestID, self.selection == selection else { return }
		if !diff.isEmpty {
			diff = ""
		}
		if imageDiff != requestedImageDiff {
			imageDiff = requestedImageDiff
		}
		displayedSelection = selection.identifier
	}

	private func finishLoad(for requestID: Int) {
		guard activeLoadRequestID == requestID else { return }
		activeLoadRequestID = nil
		isLoading = false
	}

	private func clearLoad() {
		activeLoadRequestID = nil
		isLoading = false
	}

	private func clearDisplayedDiff() {
		diff = ""
		imageDiff = nil
		displayedSelection = nil
		clearLoad()
	}
}
