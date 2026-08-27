import Combine
import DomainGitInterface
import FeatureRepositoryInterface
import Foundation

@MainActor
final class ChangesViewModel: ObservableObject {
	@Published var selectedChangeIDs: Set<WorkspaceChangeSelection> = []
	@Published var filterText = ""
	@Published var commitSubject = ""
	@Published var commitBody = ""
	@Published private(set) var isAmendingCommit = false
	@Published private(set) var changes: [WorkingTreeChange] = []
	@Published private(set) var amendChanges: [GitAmendChange] = []
	@Published private(set) var diff = ""
	@Published private(set) var imageDiff: GitImageDiff?
	@Published private(set) var conflictContent: GitConflictContent?
	@Published private(set) var conflictPreviewUnavailable = false
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingDiff = false
	@Published private(set) var isApplyingDiffLine = false

	var preferences: WorkspaceDiffPreferences {
		dependencies.preferences
	}

	private let dependencies: ChangesViewModelDependencies
	private let actions: ChangesViewModelActions
	private var operationState: RepositoryOperationState = .normal
	private var commitGraphItems: [CommitGraphItem] = []
	private var diffTask: Task<Void, Never>?
	private var mutationTask: Task<Void, Never>?
	private var displayedDiffSelection: WorkspaceChangeSelection?
	private var requestedDiffSelection: WorkspaceChangeSelection?

	init(
		dependencies: ChangesViewModelDependencies,
		actions: ChangesViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	private var contentUseCase: any RepositoryContentUseCase {
		dependencies.contentUseCase
	}

	private var changesUseCase: any RepositoryChangesUseCase {
		dependencies.changesUseCase
	}

	private var operationsUseCase: (any RepositoryOperationsUseCase)? {
		dependencies.operationsUseCase
	}

	private var externalEditorOpener: (any RepositoryExternalEditorOpening)? {
		dependencies.externalEditorOpener
	}

	private var repositoryURL: @MainActor () -> URL? {
		dependencies.repositoryURL
	}

	private var didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void {
		actions.didProduceSnapshot
	}

	private var didReceiveError: @MainActor (String) -> Void {
		actions.didReceiveError
	}

	private var didRequestConfirmation: @MainActor (PendingRepositoryConfirmation) -> Void {
		actions.didRequestConfirmation
	}

	deinit {
		diffTask?.cancel()
		mutationTask?.cancel()
	}

	var selectedStagedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains(.staged($0.id)) }
	}

	var selectedUnstagedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains(.unstaged($0.id)) }
	}

	var selectedChanges: [WorkingTreeChange] {
		let identifiers = Set(selectedChangeIDs.map(\.changeID))
		return changes.filter { identifiers.contains($0.id) }
	}

	var selectedStageableChanges: [WorkingTreeChange] {
		selectedUnstagedChanges.filter(\.hasWorkingTreeChange)
	}

	var displayedWorkingTreeChanges: [WorkingTreeChange] {
		guard isAmendingCommit else { return changes }
		return changes.filter(\.hasWorkingTreeChange)
	}

	var selectedChange: WorkingTreeChange? {
		guard selectedChangeIDs.count == 1, let selection = selectedChangeIDs.first else {
			return nil
		}
		switch selection {
		case .staged(let id), .unstaged(let id):
			return changes.first { $0.id == id }
		case .amend, .conflict:
			return nil
		}
	}

	var selectedDiffSource: GitDiffSource? {
		guard selectedChangeIDs.count == 1, let selection = selectedChangeIDs.first else {
			return nil
		}
		switch selection {
		case .staged:
			return .staged
		case .unstaged:
			return .unstaged
		case .amend, .conflict:
			return nil
		}
	}

	var selectedFileState: GitFileState? {
		guard let selectedChange else { return selectedAmendChange?.state }
		switch selectedDiffSource {
		case .staged:
			return selectedChange.indexState
		case .unstaged:
			return selectedChange.workingTreeState
		case .none:
			return nil
		}
	}

	var selectedAmendChanges: [GitAmendChange] {
		amendChanges.filter { selectedChangeIDs.contains(.amend($0.id)) }
	}

	var selectedAmendChange: GitAmendChange? {
		guard selectedChangeIDs.count == 1 else { return nil }
		return selectedAmendChanges.first
	}

	var conflicts: [GitConflict] {
		operationState.conflicts
	}

	var currentConflictLabel: String {
		switch operationState.operation?.kind {
		case .rebase:
			return "Target Branch"
		case .cherryPick:
			return "Current Branch"
		case .revert:
			return "Current Branch"
		case .merge, .none:
			return "Current"
		}
	}

	var incomingConflictLabel: String {
		switch operationState.operation?.kind {
		case .rebase:
			return "Replayed Commit"
		case .cherryPick:
			return "Picked Commit"
		case .revert:
			return "Reverted Result"
		case .merge, .none:
			return "Incoming"
		}
	}

	var oursConflictLabel: String {
		"Resolve Entire File Using \(currentConflictLabel)"
	}

	var theirsConflictLabel: String {
		"Resolve Entire File Using \(incomingConflictLabel)"
	}

	var filteredConflicts: [GitConflict] {
		conflicts.filter { matchesFilter(path: $0.path) }
	}

	var selectedConflict: GitConflict? {
		guard selectedChangeIDs.count == 1, case .conflict(let path) = selectedChangeIDs.first else {
			return nil
		}
		return conflicts.first { $0.path == path }
	}

	var selectedDiffLineAction: GitDiffLineAction? {
		guard !preferences.options.ignoresWhitespace else { return nil }
		guard let selectedChange, let selectedDiffSource else { return nil }
		if selectedDiffSource == .unstaged, selectedChange.workingTreeState == .modified {
			return .stage
		}
		if selectedDiffSource == .staged, selectedChange.indexState == .modified {
			return .unstage
		}
		return nil
	}

	var selectedDiffHunkActions: [GitDiffHunkAction] {
		guard !preferences.options.ignoresWhitespace else { return [] }
		switch selectedDiffLineAction {
		case .stage:
			return selectedChange?.workingTreeState == .modified ? [.stage, .discard] : [.stage]
		case .unstage:
			return [.unstage]
		case .none:
			return []
		}
	}

	var filteredStagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter(\.isStaged)
	}

	var filteredUnstagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter(\.hasWorkingTreeChange)
	}

	var filteredAmendChanges: [GitAmendChange] {
		amendChanges.filter { matchesFilter(path: $0.path) }
	}

	var canCommit: Bool {
		!commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& (isAmendingCommit || changes.contains(where: \.isStaged))
			&& !operationState.isDetached
			&& !isLoading
	}

	var canAmendCommit: Bool {
		!commitGraphItems.isEmpty && !operationState.isDetached && !isLoading
	}

	func apply(_ snapshot: RepositorySnapshot) {
		let changesDidChange = changes != snapshot.changes || amendChanges != snapshot.amendChanges
		if changesDidChange {
			diffTask?.cancel()
			displayedDiffSelection = nil
			requestedDiffSelection = nil
			isLoadingDiff = false
		}
		changes = snapshot.changes
		amendChanges = snapshot.amendChanges
		operationState = snapshot.operationState
		commitGraphItems = CommitGraphLayoutBuilder.build(commits: snapshot.commits)
		preserveSelection()
	}

	func reset() {
		cancelTasks()
		selectedChangeIDs = []
		changes = []
		amendChanges = []
		isAmendingCommit = false
		clearDisplayedDiff()
	}

	func cancelTasks() {
		diffTask?.cancel()
		mutationTask?.cancel()
	}

	func didSelectChanges(_ selections: Set<WorkspaceChangeSelection>) async {
		await Task.yield()
		guard !Task.isCancelled, selectedChangeIDs != selections else { return }
		selectedChangeIDs = selections
		didChangeSelectedChanges()
	}

	func didChangeSelectedChanges() {
		diffTask?.cancel()
		clearDiffLoad()

		guard
			let repositoryURL = repositoryURL(),
			selectedChangeIDs.count == 1,
			let selection = selectedChangeIDs.first
		else {
			clearDisplayedDiff()
			return
		}

		if displayedDiffSelection != nil, displayedDiffSelection != selection {
			clearDisplayedDiff()
		}
		guard displayedDiffSelection != selection, requestedDiffSelection != selection else { return }
		switch selection {
		case .staged(let id), .unstaged(let id):
			guard let change = changes.first(where: { $0.id == id }) else {
				clearDisplayedDiff()
				return
			}
			let source: GitDiffSource = selection.isStaged ? .staged : .unstaged
			requestDiff(for: change, source: source, selection: selection, at: repositoryURL)
		case .amend(let id):
			guard isAmendingCommit, let change = amendChanges.first(where: { $0.id == id }) else {
				clearDisplayedDiff()
				return
			}
			requestAmendDiff(for: change, selection: selection, at: repositoryURL)
		case .conflict(let path):
			guard let conflict = conflicts.first(where: { $0.path == path }) else {
				clearDisplayedDiff()
				return
			}
			requestConflictContent(for: conflict, selection: selection, at: repositoryURL)
		}
	}

	func didChangeDiffOptions() {
		displayedDiffSelection = nil
		requestedDiffSelection = nil
		didChangeSelectedChanges()
	}

	func didRequestStage(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let stageableChanges = changes.filter {
			requestedIDs.contains($0.id) && $0.hasWorkingTreeChange
		}
		guard let repositoryURL = repositoryURL(), !stageableChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.stage(stageableChanges, at: repositoryURL)
		}
	}

	func didRequestUnstage(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let stagedChanges = changes.filter {
			requestedIDs.contains($0.id) && $0.isStaged
		}
		guard let repositoryURL = repositoryURL(), !stagedChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.unstage(stagedChanges, at: repositoryURL)
		}
	}

	func didRequestUnstageFromAmend(_ requestedChanges: [GitAmendChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let requestedAmendChanges = amendChanges.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL = repositoryURL(), !requestedAmendChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.unstageFromAmend(requestedAmendChanges, at: repositoryURL)
		}
	}

	func didRequestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction
	) {
		guard
			let repositoryURL = repositoryURL(),
			let change = selectedChange,
			selectedDiffLineAction == action,
			!isApplyingDiffLine
		else { return }
		requestDiffLineMutation(replacing: change) {
			try await self.changesUseCase.applyDiffLine(
				selection,
				action: action,
				for: change,
				at: repositoryURL
			)
		}
	}

	func didRequestApplyDiffHunk(
		_ selection: GitDiffHunkSelection,
		action: GitDiffHunkAction
	) {
		guard
			let repositoryURL = repositoryURL(),
			let change = selectedChange,
			selectedDiffHunkActions.contains(action),
			!isApplyingDiffLine
		else { return }
		if action == .discard {
			didRequestConfirmation(.discardHunk(selection, change, preferences.options))
			return
		}
		requestDiffLineMutation(replacing: change) {
			try await self.changesUseCase.applyDiffHunk(
				selection,
				action: action,
				for: change,
				options: self.preferences.options,
				at: repositoryURL
			)
		}
	}

	func didPresentDiscardConfirmation(for changes: [WorkingTreeChange]) {
		guard !changes.isEmpty else { return }
		didRequestConfirmation(.discard(changes))
	}

	func didConfirmDiscard(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let discardableChanges = changes.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL = repositoryURL(), !discardableChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.discard(discardableChanges, at: repositoryURL)
		}
	}

	func didConfirmDiscardHunk(
		_ selection: GitDiffHunkSelection,
		change: WorkingTreeChange,
		options: GitDiffOptions
	) {
		guard let repositoryURL = repositoryURL() else { return }
		requestDiffLineMutation(replacing: change) {
			try await self.changesUseCase.applyDiffHunk(
				selection,
				action: .discard,
				for: change,
				options: options,
				at: repositoryURL
			)
		}
	}

	func didRequestCommit() {
		guard let repositoryURL = repositoryURL(), canCommit else { return }
		let subject = commitSubject.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedBody = commitBody.trimmingCharacters(in: .newlines)
		let body =
			trimmedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? ""
			: trimmedBody
		let amend = isAmendingCommit
		requestMutation {
			let snapshot = try await self.changesUseCase.commit(
				subject: subject,
				body: body,
				amend: amend,
				at: repositoryURL
			)
			self.commitSubject = ""
			self.commitBody = ""
			self.isAmendingCommit = false
			return snapshot
		}
	}

	func didRequestAmendWithoutEditingMessage() {
		guard
			let repositoryURL = repositoryURL(),
			changes.contains(where: \.isStaged),
			!operationState.isDetached,
			!isLoading
		else { return }
		requestMutation {
			try await self.changesUseCase.amendWithoutEditingMessage(at: repositoryURL)
		}
	}

	func didSetAmendingCommit(_ isAmending: Bool) {
		guard !isAmending || canAmendCommit else { return }
		isAmendingCommit = isAmending
		if isAmending, commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			commitSubject = currentCommit?.subject ?? ""
		}
		if isAmending, commitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			commitBody = currentCommit?.body ?? ""
		}
		preserveSelection()
	}

	func didResolveConflict(_ conflict: GitConflict, using resolution: GitConflictResolution) {
		guard let repositoryURL = repositoryURL(), let operationsUseCase else { return }
		requestMutation {
			try await operationsUseCase.resolve(conflict, using: resolution, at: repositoryURL)
		}
	}

	func didResolveConflictHunk(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution
	) {
		guard let repositoryURL = repositoryURL(), let operationsUseCase, !isLoading else { return }
		requestMutation {
			let snapshot = try await operationsUseCase.resolveHunk(
				hunk,
				in: conflict,
				using: resolution,
				at: repositoryURL
			)
			let content = try await operationsUseCase.loadConflictContent(
				for: conflict,
				at: repositoryURL
			)
			self.setConflictContent(content)
			return snapshot
		}
	}

	func didMarkConflictResolved(_ conflict: GitConflict) {
		guard let repositoryURL = repositoryURL(), let operationsUseCase, !isLoading else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let content = try await operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				setConflictContent(content)
				if content.hasConflictMarkers {
					didRequestConfirmation(.markConflictResolved(conflict))
					return
				}
				let snapshot = try await operationsUseCase.markResolved(
					path: conflict.path,
					at: repositoryURL
				)
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	func didConfirmMarkConflictResolved(_ conflict: GitConflict) {
		guard let repositoryURL = repositoryURL(), let operationsUseCase else { return }
		requestMutation {
			try await operationsUseCase.markResolved(path: conflict.path, at: repositoryURL)
		}
	}

	func didOpenConflictInEditor(_ conflict: GitConflict) {
		guard let repositoryURL = repositoryURL(), let externalEditorOpener else { return }
		let fileURL = repositoryURL.appending(path: conflict.path)
		guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
		do {
			let storedBundleIdentifier = UserDefaults.standard.string(
				forKey: "externalEditorBundleIdentifier"
			)
			try externalEditorOpener.openFile(
				at: fileURL,
				applicationBundleIdentifier: storedBundleIdentifier?.isEmpty == false
					? storedBundleIdentifier
					: nil
			)
		} catch {
			didReceiveError("The selected editor is unavailable. Choose another app in Settings.")
		}
	}

	private func requestDiff(
		for change: WorkingTreeChange,
		source: GitDiffSource,
		selection: WorkspaceChangeSelection,
		at repositoryURL: URL
	) {
		requestedDiffSelection = selection
		isLoadingDiff = true
		diffTask = Task {
			defer { finishDiffLoad(for: selection) }
			do {
				if DiffImageFileSupport.isSupported(path: change.path) {
					let imageDiff = try await changesUseCase.loadImageDiff(
						for: change,
						source: source,
						at: repositoryURL
					)
					updateDisplayedImageDiff(imageDiff, for: selection)
				} else {
					let diff = try await changesUseCase.loadDiff(
						for: change,
						source: source,
						options: preferences.options,
						at: repositoryURL
					)
					updateDisplayedDiff(diff, for: selection)
				}
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func requestAmendDiff(
		for change: GitAmendChange,
		selection: WorkspaceChangeSelection,
		at repositoryURL: URL
	) {
		requestedDiffSelection = selection
		isLoadingDiff = true
		diffTask = Task {
			defer { finishDiffLoad(for: selection) }
			do {
				if DiffImageFileSupport.isSupported(path: change.path) {
					let imageDiff = try await changesUseCase.loadAmendImageDiff(
						for: change,
						at: repositoryURL
					)
					updateDisplayedImageDiff(imageDiff, for: selection)
				} else {
					let diff = try await changesUseCase.loadAmendDiff(
						for: change,
						options: preferences.options,
						at: repositoryURL
					)
					updateDisplayedDiff(diff, for: selection)
				}
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func requestConflictContent(
		for conflict: GitConflict,
		selection: WorkspaceChangeSelection,
		at repositoryURL: URL
	) {
		requestedDiffSelection = selection
		isLoadingDiff = true
		diffTask = Task {
			defer { finishDiffLoad(for: selection) }
			do {
				guard let operationsUseCase else { return }
				let content = try await operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				guard selectedChangeIDs == Set([selection]) else { return }
				setConflictContent(content)
				updateDisplayedDiff(content.workingTree ?? "", for: selection)
			} catch is CancellationError {
				return
			} catch {
				guard selectedChangeIDs == Set([selection]) else { return }
				conflictContent = nil
				conflictPreviewUnavailable = true
				updateDisplayedDiff("", for: selection)
			}
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
				if let snapshot = try? await contentUseCase.loadSnapshot(at: expectedRepositoryURL) {
					didProduceSnapshot(snapshot)
				}
			}
		}
	}

	private func requestDiffLineMutation(
		replacing originalChange: WorkingTreeChange,
		_ operation: @escaping @MainActor () async throws -> [WorkingTreeChange]
	) {
		guard
			selectedChangeIDs.count == 1,
			let originalSelection = selectedChangeIDs.first,
			let originalSource = selectedDiffSource
		else { return }

		mutationTask?.cancel()
		diffTask?.cancel()
		mutationTask = Task {
			isApplyingDiffLine = true
			defer { isApplyingDiffLine = false }
			do {
				let refreshedRelatedChanges = try await operation()
				guard let repositoryURL = repositoryURL() else { return }
				try Task.checkCancellation()
				let refreshedChanges = mergingWorkingTreeChanges(
					refreshedRelatedChanges,
					replacing: originalChange
				)
				let availableSelections = availableWorkingTreeSelections(in: refreshedChanges)
				var refreshedSelection = selectedChangeIDs.intersection(availableSelections)
				if refreshedSelection.isEmpty,
					let fallbackChange = refreshedChanges.first(where: {
						originalSource == .staged ? $0.isStaged : $0.hasWorkingTreeChange
					})
				{
					refreshedSelection = [
						originalSource == .staged
							? .staged(fallbackChange.id)
							: .unstaged(fallbackChange.id)
					]
				}
				let refreshedSelectionValue =
					refreshedSelection.count == 1 ? refreshedSelection.first : nil
				let refreshedChange = refreshedSelectionValue.flatMap { selection in
					refreshedChanges.first { $0.id == selection.changeID }
				}
				let refreshedDiff: String
				if let refreshedChange, let refreshedSelectionValue {
					refreshedDiff = try await changesUseCase.loadDiff(
						for: refreshedChange,
						source: refreshedSelectionValue.isStaged ? .staged : .unstaged,
						options: preferences.options,
						at: repositoryURL
					)
				} else {
					refreshedDiff = ""
				}
				try Task.checkCancellation()
				changes = refreshedChanges
				selectedChangeIDs = refreshedSelection
				diff = refreshedDiff
				displayedDiffSelection = refreshedSelectionValue
				requestedDiffSelection = nil
				if originalSelection != refreshedSelectionValue {
					clearDiffLoad()
				}
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func mergingWorkingTreeChanges(
		_ refreshedChanges: [WorkingTreeChange],
		replacing originalChange: WorkingTreeChange
	) -> [WorkingTreeChange] {
		let relatedPaths = Set([originalChange.path, originalChange.previousPath].compactMap { $0 })
		let insertionIndex =
			changes.firstIndex { change in
				let paths = Set([change.path, change.previousPath].compactMap { $0 })
				return !relatedPaths.isDisjoint(with: paths)
			} ?? changes.endIndex
		var mergedChanges = changes.filter { change in
			let paths = Set([change.path, change.previousPath].compactMap { $0 })
			return relatedPaths.isDisjoint(with: paths)
		}
		mergedChanges.insert(
			contentsOf: refreshedChanges,
			at: min(insertionIndex, mergedChanges.endIndex)
		)
		return mergedChanges
	}

	private func preserveSelection() {
		if commitGraphItems.isEmpty {
			isAmendingCommit = false
		}
		var availableSelections = availableWorkingTreeSelections(in: displayedWorkingTreeChanges)
		availableSelections.formUnion(conflicts.map { WorkspaceChangeSelection.conflict($0.path) })
		if isAmendingCommit {
			availableSelections.formUnion(amendChanges.map { WorkspaceChangeSelection.amend($0.id) })
		}
		selectedChangeIDs.formIntersection(availableSelections)
		if selectedChangeIDs.isEmpty, let firstConflict = conflicts.first {
			selectedChangeIDs = [.conflict(firstConflict.path)]
		} else if selectedChangeIDs.isEmpty,
			let firstStagedChange = displayedWorkingTreeChanges.first(where: \.isStaged)
		{
			selectedChangeIDs = [.staged(firstStagedChange.id)]
		} else if selectedChangeIDs.isEmpty,
			let firstUnstagedChange = displayedWorkingTreeChanges.first(where: \.hasWorkingTreeChange)
		{
			selectedChangeIDs = [.unstaged(firstUnstagedChange.id)]
		} else if selectedChangeIDs.isEmpty,
			isAmendingCommit,
			let firstChangeID = amendChanges.first?.id
		{
			selectedChangeIDs = [.amend(firstChangeID)]
		}
		didChangeSelectedChanges()
	}

	private func availableWorkingTreeSelections(
		in changes: [WorkingTreeChange]
	) -> Set<WorkspaceChangeSelection> {
		var selections: Set<WorkspaceChangeSelection> = []
		for change in changes {
			if change.isStaged {
				selections.insert(.staged(change.id))
			}
			if change.hasWorkingTreeChange {
				selections.insert(.unstaged(change.id))
			}
		}
		return selections
	}

	private func updateDisplayedDiff(
		_ requestedDiff: String,
		for selection: WorkspaceChangeSelection
	) {
		guard selectedChangeIDs == Set([selection]) else { return }
		diff = requestedDiff
		imageDiff = nil
		displayedDiffSelection = selection
	}

	private func updateDisplayedImageDiff(
		_ requestedImageDiff: GitImageDiff,
		for selection: WorkspaceChangeSelection
	) {
		guard selectedChangeIDs == Set([selection]) else { return }
		diff = ""
		imageDiff = requestedImageDiff
		displayedDiffSelection = selection
	}

	private func finishDiffLoad(for selection: WorkspaceChangeSelection) {
		guard requestedDiffSelection == selection else { return }
		requestedDiffSelection = nil
		isLoadingDiff = false
	}

	private func clearDiffLoad() {
		requestedDiffSelection = nil
		isLoadingDiff = false
	}

	private func clearDisplayedDiff() {
		diff = ""
		imageDiff = nil
		displayedDiffSelection = nil
		conflictContent = nil
		conflictPreviewUnavailable = false
		clearDiffLoad()
	}

	private func setConflictContent(_ content: GitConflictContent) {
		conflictContent = content
		conflictPreviewUnavailable =
			content.workingTreeData == nil
			&& content.currentData == nil
			&& content.incomingData == nil
		diff = content.workingTree ?? ""
	}

	private var currentCommit: GitCommit? {
		commitGraphItems.first {
			$0.commit.references.contains { reference in
				reference == "HEAD" || reference.hasPrefix("HEAD -> ")
			}
		}?.commit ?? commitGraphItems.first?.commit
	}

	private var filteredWorkingTreeChanges: [WorkingTreeChange] {
		let conflictPaths = Set(conflicts.map(\.path))
		return displayedWorkingTreeChanges.filter {
			!conflictPaths.contains($0.path) && matchesFilter(path: $0.path)
		}
	}

	private func matchesFilter(path: String) -> Bool {
		let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return true }
		return path.localizedCaseInsensitiveContains(query)
	}
}
