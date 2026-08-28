import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class ChangesViewModel: ObservableObject {
	@Published var selectedChangeIDs: Set<WorkspaceChangeSelection> = []
	@Published var filterText = ""
	@Published private(set) var isAmendingCommit = false
	@Published public private(set) var changes: [WorkingTreeChange] = []
	@Published private(set) var amendChanges: [GitAmendChange] = []
	@Published public private(set) var isLoading = false
	@Published var pendingConfirmation: ChangesConfirmation?

	private let dependencies: ChangesViewModelDependencies
	private let actions: ChangesViewModelActions
	private var operationState: RepositoryOperationState = .normal
	private var mutationTask: Task<Void, Never>?

	public init(
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

	public func apply(_ snapshot: RepositorySnapshot) {
		changes = snapshot.changes
		amendChanges = snapshot.amendChanges
		operationState = snapshot.operationState
		preserveSelection(forceReload: true)
	}

	public func reset() {
		cancelTasks()
		didSelectConflict(nil)
		selectedChangeIDs = []
		changes = []
		amendChanges = []
		isAmendingCommit = false
		didSelectDiff(nil, false)
	}

	func cancelTasks() {
		mutationTask?.cancel()
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
		changes = refreshedChanges
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
