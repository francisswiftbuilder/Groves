import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class ChangesViewModel: ObservableObject {
	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void
		public let didSelectConflict: @MainActor (GitConflict?) -> Void
		public let didSelectDiff: @MainActor (ChangesDiffSelection?, Bool) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void,
			didSelectConflict: @escaping @MainActor (GitConflict?) -> Void,
			didSelectDiff: @escaping @MainActor (ChangesDiffSelection?, Bool) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
			self.didSelectConflict = didSelectConflict
			self.didSelectDiff = didSelectDiff
		}
	}

	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase
		public let changesUseCase: any RepositoryChangesUseCase
		public let repositoryURL: @MainActor () -> URL?

		public init(
			contentUseCase: any RepositoryContentUseCase,
			changesUseCase: any RepositoryChangesUseCase,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.contentUseCase = contentUseCase
			self.changesUseCase = changesUseCase
			self.repositoryURL = repositoryURL
		}
	}

	@Published var selectedChangeIDs: Set<WorkspaceChangeSelection> = []
	@Published var filterText = ""
	@Published private(set) var isAmendingCommit = false
	@Published private var snapshotState = ChangesSnapshotState.empty
	@Published public private(set) var isLoading = false
	@Published var pendingConfirmation: ChangesConfirmation?

	private let dependencies: Dependencies
	private let actions: Actions
	private var mutationTask: Task<Void, Never>?
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0

	public init(
		dependencies: Dependencies,
		actions: Actions
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

	private var repositoryURL: @MainActor () -> URL? {
		dependencies.repositoryURL
	}

	private var didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void {
		actions.didProduceSnapshot
	}

	private var didReceiveError: @MainActor (String) -> Void {
		actions.didReceiveError
	}

	private var didSelectConflict: @MainActor (GitConflict?) -> Void {
		actions.didSelectConflict
	}

	private var didSelectDiff: @MainActor (ChangesDiffSelection?, Bool) -> Void {
		actions.didSelectDiff
	}

	deinit {
		mutationTask?.cancel()
	}

	public var changes: [WorkingTreeChange] {
		snapshotState.changes
	}

	var amendChanges: [GitAmendChange] {
		snapshotState.amendChanges
	}

	public var conflicts: [GitConflict] {
		snapshotState.conflicts
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

	var selectedDiffSourceID: String? {
		guard selectedChangeIDs.count == 1, let selection = selectedChangeIDs.first else {
			return nil
		}
		switch selection {
		case .staged(let id): return "staged:\(id)"
		case .unstaged(let id): return "unstaged:\(id)"
		case .amend(let id): return "amend:\(id)"
		case .conflict: return nil
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

	var filteredConflicts: [GitConflict] {
		conflicts.filter { matchesFilter(path: $0.path) }
	}

	var selectedConflict: GitConflict? {
		guard selectedChangeIDs.count == 1, case .conflict(let path) = selectedChangeIDs.first else {
			return nil
		}
		return conflicts.first { $0.path == path }
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

	public func apply(
		_ snapshot: RepositorySnapshot,
		revalidatesSelectedDiff: Bool = true
	) {
		let nextState = ChangesSnapshotState(
			changes: snapshot.changes,
			amendChanges: snapshot.amendChanges,
			conflicts: snapshot.operationState.conflicts
		)
		let didChangeState = snapshotState != nextState
		guard didChangeState || revalidatesSelectedDiff else { return }
		if didChangeState {
			snapshotState = nextState
		}
		preserveSelection(forceReload: didChangeState || revalidatesSelectedDiff)
	}

	public func reset() {
		cancelTasks()
		filterText = ""
		pendingConfirmation = nil
		didSelectConflict(nil)
		selectedChangeIDs = []
		snapshotState = .empty
		isAmendingCommit = false
		didSelectDiff(nil, false)
	}

	func cancelTasks() {
		mutationTask?.cancel()
		mutationTask = nil
		activeMutationRequestID = nil
		isLoading = false
	}

	public func didSelectChanges(_ selections: Set<WorkspaceChangeSelection>) async {
		await Task.yield()
		guard !Task.isCancelled, selectedChangeIDs != selections else { return }
		selectedChangeIDs = selections
		didChangeSelectedChanges()
	}

	func didChangeSelectedChanges(forceReload: Bool = false) {
		guard
			selectedChangeIDs.count == 1,
			let selection = selectedChangeIDs.first
		else {
			didSelectConflict(nil)
			didSelectDiff(nil, false)
			return
		}

		switch selection {
		case .staged(let id), .unstaged(let id):
			didSelectConflict(nil)
			guard let change = changes.first(where: { $0.id == id }) else {
				didSelectDiff(nil, false)
				return
			}
			let source: GitDiffSource = selection.isStaged ? .staged : .unstaged
			didSelectDiff(.workingTree(selection, change, source), forceReload)
		case .amend(let id):
			didSelectConflict(nil)
			guard isAmendingCommit, let change = amendChanges.first(where: { $0.id == id }) else {
				didSelectDiff(nil, false)
				return
			}
			didSelectDiff(.amend(selection, change), forceReload)
		case .conflict(let path):
			guard let conflict = conflicts.first(where: { $0.path == path }) else {
				didSelectConflict(nil)
				didSelectDiff(nil, false)
				return
			}
			didSelectDiff(nil, false)
			didSelectConflict(conflict)
		}
	}

	public func didChangeDiffOptions() {
		guard
			selectedChangeIDs.count == 1,
			let selection = selectedChangeIDs.first
		else {
			didSelectDiff(nil, true)
			return
		}
		switch selection {
		case .staged(let id), .unstaged(let id):
			guard let change = changes.first(where: { $0.id == id }) else { return }
			let source: GitDiffSource = selection.isStaged ? .staged : .unstaged
			didSelectDiff(.workingTree(selection, change, source), true)
		case .amend(let id):
			guard isAmendingCommit, let change = amendChanges.first(where: { $0.id == id }) else {
				return
			}
			didSelectDiff(.amend(selection, change), true)
		case .conflict:
			didSelectDiff(nil, true)
		}
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

	func didPresentDiscardConfirmation(for changes: [WorkingTreeChange]) {
		guard !changes.isEmpty else { return }
		pendingConfirmation = .discard(changes)
	}

	func didConfirmDiscard(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let discardableChanges = changes.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL = repositoryURL(), !discardableChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.discard(discardableChanges, at: repositoryURL)
		}
	}

	public func didSetAmendingCommit(_ isAmending: Bool) {
		guard isAmendingCommit != isAmending else { return }
		isAmendingCommit = isAmending
		preserveSelection()
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
		pendingConfirmation = nil
		didConfirmDiscard(confirmation.changes)
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL() else { return }
		mutationTask?.cancel()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				let snapshot = try await operation()
				guard let self, self.activeMutationRequestID == requestID else { return }
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, self.activeMutationRequestID == requestID else { return }
				didReceiveError(error.localizedDescription)
				if let snapshot = try? await contentUseCase.loadSnapshot(at: expectedRepositoryURL) {
					guard activeMutationRequestID == requestID else { return }
					didProduceSnapshot(snapshot)
				}
			}
		}
	}

	private func beginMutation() -> Int {
		mutationRequestSequence += 1
		activeMutationRequestID = mutationRequestSequence
		isLoading = true
		return mutationRequestSequence
	}

	private func finishMutation(id: Int) {
		guard activeMutationRequestID == id else { return }
		activeMutationRequestID = nil
		mutationTask = nil
		isLoading = false
	}

	public func didApplyDiffMutation(
		_ refreshedRelatedChanges: [WorkingTreeChange],
		replacing originalChange: WorkingTreeChange,
		source: GitDiffSource
	) {
		let refreshedChanges = mergingWorkingTreeChanges(
			refreshedRelatedChanges,
			replacing: originalChange
		)
		let availableSelections = availableWorkingTreeSelections(in: refreshedChanges)
		var refreshedSelection = selectedChangeIDs.intersection(availableSelections)
		if refreshedSelection.isEmpty,
			let fallbackChange = refreshedChanges.first(where: {
				source == .staged ? $0.isStaged : $0.hasWorkingTreeChange
			})
		{
			refreshedSelection = [
				source == .staged
					? .staged(fallbackChange.id)
					: .unstaged(fallbackChange.id)
			]
		}
		snapshotState = ChangesSnapshotState(
			changes: refreshedChanges,
			amendChanges: amendChanges,
			conflicts: conflicts
		)
		selectedChangeIDs = refreshedSelection
		didChangeSelectedChanges(forceReload: true)
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

	private func preserveSelection(forceReload: Bool = false) {
		var availableSelections = availableWorkingTreeSelections(in: displayedWorkingTreeChanges)
		availableSelections.formUnion(conflicts.map { WorkspaceChangeSelection.conflict($0.path) })
		if isAmendingCommit {
			availableSelections.formUnion(amendChanges.map { WorkspaceChangeSelection.amend($0.id) })
		}
		var selection = selectedChangeIDs.intersection(availableSelections)
		if selection.isEmpty, let firstConflict = conflicts.first {
			selection = [.conflict(firstConflict.path)]
		} else if selection.isEmpty,
			let firstStagedChange = displayedWorkingTreeChanges.first(where: \.isStaged)
		{
			selection = [.staged(firstStagedChange.id)]
		} else if selection.isEmpty,
			let firstUnstagedChange = displayedWorkingTreeChanges.first(where: \.hasWorkingTreeChange)
		{
			selection = [.unstaged(firstUnstagedChange.id)]
		} else if selection.isEmpty,
			isAmendingCommit,
			let firstChangeID = amendChanges.first?.id
		{
			selection = [.amend(firstChangeID)]
		}
		if selectedChangeIDs != selection {
			selectedChangeIDs = selection
		}
		didChangeSelectedChanges(forceReload: forceReload)
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
