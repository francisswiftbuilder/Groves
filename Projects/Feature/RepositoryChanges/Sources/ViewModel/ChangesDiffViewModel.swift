import Combine
import DomainGitInterface
import FeatureRepositoryDiff
import FeatureRepositoryInterface
import Foundation

@MainActor
public final class ChangesDiffViewModel: ObservableObject {
	@Published private(set) var diff = ""
	@Published private(set) var imageDiff: GitImageDiff?
	@Published public private(set) var isLoading = false
	@Published public private(set) var isApplyingAction = false
	@Published var pendingConfirmation: ChangesDiffConfirmation?

	var preferences: WorkspaceDiffPreferences {
		dependencies.preferences
	}

	private let dependencies: ChangesDiffViewModelDependencies
	private let actions: ChangesDiffViewModelActions
	private var selection: ChangesDiffSelection?
	private var displayedSelection: WorkspaceChangeSelection?
	private var requestedSelection: WorkspaceChangeSelection?
	private var loadTask: Task<Void, Never>?
	private var mutationTask: Task<Void, Never>?

	public init(
		dependencies: ChangesDiffViewModelDependencies,
		actions: ChangesDiffViewModelActions
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
		if displayedSelection != selection.identifier {
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
	}

	func didRequestApplyDiffLine(
		_ lineSelection: GitDiffLineSelection,
		action: GitDiffLineAction
	) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			case .workingTree(_, let change, let source) = selection,
			selectedDiffLineAction == action,
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
			selectedChange == confirmation.change
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

	private func requestDiff(for selection: ChangesDiffSelection, at repositoryURL: URL) {
		let identifier = selection.identifier
		requestedSelection = identifier
		isLoading = true
		loadTask = Task {
			defer { finishLoad(for: identifier) }
			do {
				switch selection {
				case .workingTree(_, let change, let source):
					try await loadDiff(for: change, source: source, selection: selection, at: repositoryURL)
				case .amend(_, let change):
					try await loadDiff(for: change, selection: selection, at: repositoryURL)
				}
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
			}
		}
	}

	private func loadDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		selection: ChangesDiffSelection,
		at repositoryURL: URL
	) async throws {
		if DiffImageFileSupport.isSupported(path: change.path) {
			let imageDiff = try await dependencies.changesUseCase.loadImageDiff(
				for: change,
				source: source,
				at: repositoryURL
			)
			updateDisplayedImageDiff(imageDiff, for: selection)
		} else {
			let diff = try await dependencies.changesUseCase.loadDiff(
				for: change,
				source: source,
				options: preferences.options,
				at: repositoryURL
			)
			updateDisplayedDiff(diff, for: selection)
		}
	}

	private func loadDiff(
		for change: GitAmendChange,
		selection: ChangesDiffSelection,
		at repositoryURL: URL
	) async throws {
		if DiffImageFileSupport.isSupported(path: change.path) {
			let imageDiff = try await dependencies.changesUseCase.loadAmendImageDiff(
				for: change,
				at: repositoryURL
			)
			updateDisplayedImageDiff(imageDiff, for: selection)
		} else {
			let diff = try await dependencies.changesUseCase.loadAmendDiff(
				for: change,
				options: preferences.options,
				at: repositoryURL
			)
			updateDisplayedDiff(diff, for: selection)
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
		mutationTask = Task {
			isApplyingAction = true
			defer { isApplyingAction = false }
			do {
				let refreshedChanges = try await operation()
				try Task.checkCancellation()
				actions.didApplyMutation(refreshedChanges, change, source)
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
			}
		}
	}

	private func updateDisplayedDiff(
		_ requestedDiff: String,
		for selection: ChangesDiffSelection
	) {
		guard self.selection == selection else { return }
		diff = requestedDiff
		imageDiff = nil
		displayedSelection = selection.identifier
	}

	private func updateDisplayedImageDiff(
		_ requestedImageDiff: GitImageDiff,
		for selection: ChangesDiffSelection
	) {
		guard self.selection == selection else { return }
		diff = ""
		imageDiff = requestedImageDiff
		displayedSelection = selection.identifier
	}

	private func finishLoad(for selection: WorkspaceChangeSelection) {
		guard requestedSelection == selection else { return }
		requestedSelection = nil
		isLoading = false
	}

	private func clearLoad() {
		requestedSelection = nil
		isLoading = false
	}

	private func clearDisplayedDiff() {
		diff = ""
		imageDiff = nil
		displayedSelection = nil
		clearLoad()
	}
}
