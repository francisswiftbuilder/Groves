import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

@MainActor
final class WorkspaceViewModel: ObservableObject {
	@Published var selectedSection: WorkspaceSection? = .changes
	@Published var selectedChangeIDs: Set<WorkspaceChangeSelection> = []
	@Published var selectedCommitID: String?
	@Published var selectedBranchID: String?
	@Published var selectedRemoteID: String?
	@Published var selectedStashID: String?
	@Published private(set) var selectedTreeNodeID: String?
	@Published var selectedCommitFileID: CommitDiffFile.ID?
	@Published var expandedTreeNodeIDs: Set<String> = []
	@Published var expandedSidebarGroups: Set<RepositorySidebarGroup> = []
	@Published var changeFilterText = ""
	@Published private(set) var pendingDiscardChanges: [WorkingTreeChange]?
	@Published var commitSubject = ""
	@Published var commitBody = ""
	@Published private(set) var isAmendingCommit = false
	@Published var newBranchName = ""
	@Published var isPresentingNewBranch = false
	@Published var newStashMessage = ""
	@Published private(set) var repositoryURL: URL?
	@Published private(set) var changes: [WorkingTreeChange] = []
	@Published private(set) var amendChanges: [GitAmendChange] = []
	@Published private(set) var commitGraphItems: [CommitGraphItem] = []
	@Published private(set) var branches: [GitBranch] = []
	@Published private(set) var remotes: [GitRemote] = []
	@Published private(set) var operationState: RepositoryOperationState = .normal
	@Published private(set) var tags: [GitTag] = []
	@Published private(set) var stashes: [GitStash] = []
	@Published private(set) var fileTree: [RepositoryTreeNode] = []
	@Published private(set) var diff = ""
	@Published private(set) var selectedCommitFiles: [CommitDiffFile] = []
	@Published private(set) var historyFocusRequest: HistoryFocusRequest?
	@Published private(set) var filePreview: RepositoryFilePreview = .none
	@Published private(set) var isLoading = false
	@Published private(set) var isLoadingContent: Bool
	@Published private(set) var isLoadingDiff = false
	@Published private(set) var isLoadingCommitDiff = false
	@Published private(set) var isApplyingDiffLine = false
	@Published var alertMessage: String?

	private let contentUseCase: any RepositoryContentUseCase
	private let changesUseCase: any RepositoryChangesUseCase
	private let referencesUseCase: any RepositoryReferencesUseCase
	private let stashesUseCase: any RepositoryStashesUseCase
	private var refreshTask: Task<Void, Never>?
	private var automaticRefreshTask: Task<Void, Never>?
	private var diffTask: Task<Void, Never>?
	private var commitDiffTask: Task<Void, Never>?
	private var filePreviewTask: Task<Void, Never>?
	private var displayedDiffSelection: WorkspaceChangeSelection?
	private var requestedDiffSelection: WorkspaceChangeSelection?
	private var displayedCommitDiffID: String?
	private var requestedCommitDiffID: String?
	private var contentLoadID: UUID?

	init(
		contentUseCase: any RepositoryContentUseCase,
		changesUseCase: any RepositoryChangesUseCase,
		referencesUseCase: any RepositoryReferencesUseCase,
		stashesUseCase: any RepositoryStashesUseCase,
		repositoryURL: URL? = nil
	) {
		self.contentUseCase = contentUseCase
		self.changesUseCase = changesUseCase
		self.referencesUseCase = referencesUseCase
		self.stashesUseCase = stashesUseCase
		self.repositoryURL = repositoryURL
		isLoadingContent = repositoryURL != nil
	}

	deinit {
		refreshTask?.cancel()
		automaticRefreshTask?.cancel()
		diffTask?.cancel()
		commitDiffTask?.cancel()
		filePreviewTask?.cancel()
	}

	var repositoryName: String {
		repositoryURL?.lastPathComponent ?? "No Repository"
	}

	var currentBranchName: String {
		guard operationState != .detachedHead else { return "Detached HEAD" }
		return currentBranch?.name ?? "No Branch"
	}

	var currentBranchStatus: String {
		guard let currentBranch else { return operationStateTitle }
		var components = [currentBranch.name]
		if let upstream = currentBranch.upstream {
			components.append(upstream)
		}
		if currentBranch.aheadCount > 0 {
			components.append("↑\(currentBranch.aheadCount)")
		}
		if currentBranch.behindCount > 0 {
			components.append("↓\(currentBranch.behindCount)")
		}
		if operationState != .normal {
			components.append(operationStateTitle)
		}
		return components.joined(separator: " · ")
	}

	var currentBranch: GitBranch? {
		branches.first(where: \.isCurrent)
	}

	var pushAction: RepositoryPushAction {
		referencesUseCase.pushAction(
			currentBranch: currentBranch,
			remotes: remotes,
			operationState: operationState
		)
	}

	var selectedStagedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains(.staged($0.id)) }
	}

	var selectedUnstagedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains(.unstaged($0.id)) }
	}

	var selectedChanges: [WorkingTreeChange] {
		let selectedIDs = Set(selectedChangeIDs.map(\.changeID))
		return changes.filter { selectedIDs.contains($0.id) }
	}

	var selectedStageableChanges: [WorkingTreeChange] {
		selectedUnstagedChanges.filter(\.hasWorkingTreeChange)
	}

	var displayedWorkingTreeChanges: [WorkingTreeChange] {
		guard isAmendingCommit else { return changes }
		return changes.filter(\.hasWorkingTreeChange)
	}

	var selectedChange: WorkingTreeChange? {
		guard selectedChangeIDs.count == 1 else { return nil }
		return changes.first { $0.id == selectedChangeIDs.first?.changeID }
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
		case .amend:
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

	var selectedDiffLineAction: GitDiffLineAction? {
		guard let selectedChange, let selectedDiffSource else { return nil }
		if selectedDiffSource == .unstaged, selectedChange.workingTreeState == .modified {
			return .stage
		}
		if selectedDiffSource == .staged, selectedChange.indexState == .modified {
			return .unstage
		}
		return nil
	}

	var selectedBranch: GitBranch? {
		branches.first { $0.id == selectedBranchID }
	}

	var selectedRemote: GitRemote? {
		remotes.first { $0.id == selectedRemoteID }
	}

	var remoteBranches: [GitRemoteBranch] {
		remotes.flatMap(\.branches)
	}

	var selectedCommit: GitCommit? {
		commitGraphItems.first { $0.id == selectedCommitID }?.commit
	}

	var selectedCommitFile: CommitDiffFile? {
		guard !selectedCommitFiles.isEmpty else { return nil }
		return selectedCommitFiles.first { $0.id == selectedCommitFileID }
			?? selectedCommitFiles.first
	}

	var visibleTreeItems: [RepositoryTreeItem] {
		RepositoryTreeLayoutBuilder.build(
			nodes: fileTree,
			expandedNodeIDs: expandedTreeNodeIDs
		)
	}

	var selectedTreeItem: RepositoryTreeItem? {
		visibleTreeItems.first { $0.id == selectedTreeNodeID }
	}

	var filteredStagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter(\.isStaged)
	}

	var filteredUnstagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter(\.hasWorkingTreeChange)
	}

	var filteredAmendChanges: [GitAmendChange] {
		amendChanges.filter { matchesChangeFilter(path: $0.path) }
	}

	var discardConfirmationTitle: String {
		guard let pendingDiscardChanges else { return "Discard Changes?" }
		guard pendingDiscardChanges.count == 1, let change = pendingDiscardChanges.first else {
			return "Discard Changes to \(pendingDiscardChanges.count) Files?"
		}
		let fileName = URL(fileURLWithPath: change.path).lastPathComponent
		return "Discard Changes to “\(fileName)”?"
	}

	var selectedStash: GitStash? {
		stashes.first { $0.id == selectedStashID }
	}

	var canCommit: Bool {
		!commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& (isAmendingCommit || changes.contains(where: \.isStaged))
			&& !isLoading
	}

	var canAmendCommit: Bool {
		commitGraphItems.isEmpty == false && !isLoading
	}

	private var operationStateTitle: String {
		switch operationState {
		case .normal:
			return "No Branch"
		case .detachedHead:
			return "Detached HEAD"
		case .mergeInProgress:
			return "Merge in Progress"
		case .rebaseInProgress:
			return "Rebase in Progress"
		case .cherryPickInProgress:
			return "Cherry-pick in Progress"
		case .revertInProgress:
			return "Revert in Progress"
		case .conflicted:
			return "Conflicts"
		}
	}

	func didSelectSection(_ section: WorkspaceSection) {
		selectedSection = section
	}

	func didSelectCommit(_ commitID: String?) async {
		await Task.yield()
		guard !Task.isCancelled, selectedCommitID != commitID else { return }
		selectedCommitID = commitID
		selectedCommitFileID = nil
		didChangeSelectedCommit()
	}

	func didSelectCommitFile(_ fileID: CommitDiffFile.ID?) async {
		await Task.yield()
		guard !Task.isCancelled, selectedCommitFileID != fileID else { return }
		selectedCommitFileID = fileID
	}

	func didSelectChanges(_ selections: Set<WorkspaceChangeSelection>) async {
		await Task.yield()
		guard !Task.isCancelled, selectedChangeIDs != selections else { return }
		selectedChangeIDs = selections
		didChangeSelectedChanges()
	}

	func didPresentDiscardConfirmation(for changes: [WorkingTreeChange]) {
		guard !changes.isEmpty else { return }
		pendingDiscardChanges = changes
	}

	func didDismissDiscardConfirmation() {
		pendingDiscardChanges = nil
	}

	func didConfirmDiscardChanges() {
		guard let pendingDiscardChanges else { return }
		self.pendingDiscardChanges = nil
		didRequestDiscard(pendingDiscardChanges)
	}

	func didPresentNewBranch() {
		newBranchName = ""
		isPresentingNewBranch = true
	}

	func didDismissNewBranch() {
		newBranchName = ""
		isPresentingNewBranch = false
	}

	func didPrepareSidebar(repositoryID: RepositoryTab.ID) {
		var groups = expandedSidebarGroups
		groups.formUnion(
			RepositorySidebarGroupKind.allCases.map {
				RepositorySidebarGroup(repositoryID: repositoryID, kind: $0)
			}
		)
		guard
			let selectedSection,
			let kind = RepositorySidebarGroupKind(section: selectedSection)
		else {
			if groups != expandedSidebarGroups {
				expandedSidebarGroups = groups
			}
			return
		}
		groups.insert(RepositorySidebarGroup(repositoryID: repositoryID, kind: kind))
		if groups != expandedSidebarGroups {
			expandedSidebarGroups = groups
		}
	}

	func setSidebarGroup(_ group: RepositorySidebarGroup, isExpanded: Bool) {
		if isExpanded {
			guard !expandedSidebarGroups.contains(group) else { return }
			expandedSidebarGroups.insert(group)
		} else {
			guard expandedSidebarGroups.contains(group) else { return }
			expandedSidebarGroups.remove(group)
		}
	}

	func setTreeNode(_ nodeID: String, isExpanded: Bool) {
		if isExpanded {
			guard !expandedTreeNodeIDs.contains(nodeID) else { return }
			expandedTreeNodeIDs.insert(nodeID)
		} else {
			guard expandedTreeNodeIDs.contains(nodeID) else { return }
			expandedTreeNodeIDs.remove(nodeID)
		}
	}

	func didSelectTreeNode(id: String?) async {
		await Task.yield()
		guard !Task.isCancelled, selectedTreeNodeID != id else { return }
		didSelectTreeNode(requestTreeNode(id: id, in: fileTree))
	}

	func didChooseRepository(_ url: URL) {
		refreshTask?.cancel()
		let loadID = beginContentLoad()
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }

			do {
				if repositoryURL != url {
					diffTask?.cancel()
					commitDiffTask?.cancel()
					selectedChangeIDs = []
					selectedCommitID = nil
					selectedCommitFileID = nil
					selectedTreeNodeID = nil
					expandedTreeNodeIDs = []
					expandedSidebarGroups = []
					clearDisplayedDiff()
					clearDisplayedCommitDiff()
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
					guard let self, !self.isLoading, !self.isApplyingDiffLine else { return }
					try await self.requestAllContent(at: repositoryURL)
				} catch is CancellationError {
					return
				} catch {}
			}
		}
	}

	func didChangeSelectedChanges() {
		diffTask?.cancel()
		clearDiffLoad()

		guard
			let repositoryURL,
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
			requestedDiffSelection = selection
			isLoadingDiff = true
			diffTask = Task {
				defer { finishDiffLoad(for: selection) }
				do {
					let requestedDiff = try await changesUseCase.loadDiff(
						for: change,
						source: source,
						at: repositoryURL
					)
					updateDisplayedDiff(requestedDiff, for: selection)
				} catch is CancellationError {
					return
				} catch {
					alertMessage = error.localizedDescription
				}
			}
		case .amend(let id):
			guard isAmendingCommit, let change = amendChanges.first(where: { $0.id == id }) else {
				clearDisplayedDiff()
				return
			}
			requestedDiffSelection = selection
			isLoadingDiff = true
			diffTask = Task {
				defer { finishDiffLoad(for: selection) }
				do {
					let requestedDiff = try await changesUseCase.loadAmendDiff(
						for: change,
						at: repositoryURL
					)
					updateDisplayedDiff(requestedDiff, for: selection)
				} catch is CancellationError {
					return
				} catch {
					alertMessage = error.localizedDescription
				}
			}
		}
	}

	func didChangeSelectedCommit() {
		guard let repositoryURL, let commit = selectedCommit else {
			commitDiffTask?.cancel()
			requestedCommitDiffID = nil
			isLoadingCommitDiff = false
			selectedCommitFileID = nil
			clearDisplayedCommitDiff()
			return
		}
		guard displayedCommitDiffID != commit.id, requestedCommitDiffID != commit.id else {
			return
		}

		commitDiffTask?.cancel()
		if displayedCommitDiffID != commit.id {
			clearDisplayedCommitDiff()
		}
		requestedCommitDiffID = commit.id
		isLoadingCommitDiff = true

		commitDiffTask = Task {
			defer {
				if requestedCommitDiffID == commit.id {
					requestedCommitDiffID = nil
					isLoadingCommitDiff = false
				}
			}
			do {
				let requestedDiff = try await changesUseCase.loadCommitDiff(
					for: commit,
					at: repositoryURL
				)
				let requestedFiles = await Task.detached(priority: .userInitiated) {
					CommitDiffFileParser.parse(requestedDiff)
				}.value
				guard selectedCommitID == commit.id else { return }
				selectedCommitFiles = requestedFiles
				preserveSelectedCommitFile()
				displayedCommitDiffID = commit.id
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	func didSelectTreeNode(_ node: RepositoryTreeNode?) {
		selectedTreeNodeID = node?.id
		filePreviewTask?.cancel()
		filePreview = .none

		guard let node, !node.isDirectory, let repositoryURL else { return }

		filePreview = .loading
		filePreviewTask = Task {
			do {
				let data = try await contentUseCase.loadFileContents(
					at: node.path,
					in: repositoryURL
				)
				guard !Task.isCancelled, selectedTreeNodeID == node.id else { return }
				filePreview = RepositoryFilePreview.make(path: node.path, data: data)
			} catch is CancellationError {
				return
			} catch {
				guard selectedTreeNodeID == node.id else { return }
				filePreview = .failure(error.localizedDescription)
			}
		}
	}

	func didRequestStage(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let stageableChanges = changes.filter {
			requestedIDs.contains($0.id) && $0.hasWorkingTreeChange
		}
		guard let repositoryURL, !stageableChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.stage(stageableChanges, at: repositoryURL)
		}
	}

	func didRequestUnstage(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let stagedChanges = changes.filter {
			requestedIDs.contains($0.id) && $0.isStaged
		}
		guard let repositoryURL, !stagedChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.unstage(stagedChanges, at: repositoryURL)
		}
	}

	func didRequestUnstageFromAmend(_ requestedChanges: [GitAmendChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let amendChanges = amendChanges.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL, !amendChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.unstageFromAmend(
				amendChanges,
				at: repositoryURL
			)
		}
	}

	func didRequestApplyDiffLine(
		_ selection: GitDiffLineSelection,
		action: GitDiffLineAction
	) {
		guard
			let repositoryURL,
			let change = selectedChange,
			selectedDiffLineAction == action,
			!isApplyingDiffLine
		else { return }
		requestDiffLineMutation {
			try await self.changesUseCase.applyDiffLine(
				selection,
				action: action,
				for: change,
				at: repositoryURL
			)
		}
	}

	func didRequestDiscard(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let discardableChanges = changes.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL, !discardableChanges.isEmpty else { return }
		requestMutation {
			try await self.changesUseCase.discard(discardableChanges, at: repositoryURL)
		}
	}

	func didRequestCommit() {
		guard let repositoryURL, canCommit else { return }
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

	func didSetAmendingCommit(_ isAmending: Bool) {
		guard !isAmending || canAmendCommit else { return }
		isAmendingCommit = isAmending
		if isAmending,
			commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			commitSubject = currentCommit?.subject ?? ""
		}
		if isAmending,
			commitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			commitBody = currentCommit?.body ?? ""
		}
		preserveChangeSelection()
	}

	func didRequestSwitchBranch() {
		guard let repositoryURL, let branch = selectedBranch, !branch.isCurrent else { return }
		requestMutation {
			try await self.referencesUseCase.switchBranch(
				named: branch.name,
				at: repositoryURL
			)
		}
	}

	func didRequestCreateBranch() {
		guard let repositoryURL else { return }
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		requestMutation {
			let snapshot = try await self.referencesUseCase.createBranch(
				named: name,
				at: repositoryURL
			)
			self.newBranchName = ""
			self.isPresentingNewBranch = false
			return snapshot
		}
	}

	func didRequestCreateLocalBranch(from remoteBranch: GitRemoteBranch) {
		guard
			let repositoryURL,
			!branches.contains(where: { $0.name == remoteBranch.name })
		else { return }
		requestMutation {
			try await self.referencesUseCase.createTrackingBranch(
				named: remoteBranch.name,
				tracking: remoteBranch.fullName,
				at: repositoryURL
			)
		}
	}

	func didRequestDeleteBranch() {
		guard let repositoryURL, let branch = selectedBranch, !branch.isCurrent else { return }
		requestMutation {
			try await self.referencesUseCase.deleteBranch(
				named: branch.name,
				at: repositoryURL
			)
		}
	}

	func didOpenBranch(_ branch: GitBranch) {
		guard
			let item = commitGraphItems.first(where: {
				$0.commit.shortHash == branch.shortHash || $0.commit.hash.hasPrefix(branch.shortHash)
			})
		else {
			alertMessage = "The latest commit for branch \(branch.name) is not available in History."
			return
		}

		clearDisplayedCommitDiff()
		selectedCommitID = item.id
		didChangeSelectedCommit()
		selectedBranchID = branch.id
		historyFocusRequest = HistoryFocusRequest(commitID: item.id, isAnimated: false)
		selectedSection = .history
	}

	func didOpenRemoteBranch(_ branch: GitRemoteBranch) {
		guard let item = commitGraphItems.first(where: { $0.commit.hash == branch.hash }) else {
			alertMessage =
				"The latest commit for remote branch \(branch.fullName) is not available in History."
			return
		}

		clearDisplayedCommitDiff()
		selectedCommitID = item.id
		didChangeSelectedCommit()
		selectedRemoteID = branch.remoteName
		historyFocusRequest = HistoryFocusRequest(commitID: item.id, isAnimated: false)
		selectedSection = .history
	}

	func didOpenTag(_ tag: GitTag) {
		guard let item = commitGraphItems.first(where: { $0.commit.hash == tag.targetHash }) else {
			alertMessage = "The commit for tag \(tag.name) is not available in History."
			return
		}

		clearDisplayedCommitDiff()
		selectedCommitID = item.id
		didChangeSelectedCommit()
		historyFocusRequest = HistoryFocusRequest(commitID: item.id, isAnimated: false)
		selectedSection = .history
	}

	func didRequestCreateStash() {
		guard let repositoryURL, !changes.isEmpty else { return }
		let message = newStashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		requestMutation {
			let snapshot = try await self.stashesUseCase.createStash(
				message: message,
				at: repositoryURL
			)
			self.newStashMessage = ""
			return snapshot
		}
	}

	func didRequestApplyStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.stashesUseCase.applyStash(stash, at: repositoryURL)
		}
	}

	func didRequestPopStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.stashesUseCase.popStash(stash, at: repositoryURL)
		}
	}

	func didRequestDropStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.stashesUseCase.dropStash(stash, at: repositoryURL)
		}
	}

	func didRequestPull() {
		guard let repositoryURL else { return }
		requestMutation {
			try await self.referencesUseCase.pull(at: repositoryURL)
		}
	}

	func didRequestFetchAll() {
		guard let repositoryURL else { return }
		requestMutation {
			try await self.referencesUseCase.fetchAll(at: repositoryURL)
		}
	}

	func didRequestFetch(remoteName: String) {
		guard let repositoryURL, remotes.contains(where: { $0.name == remoteName }) else { return }
		requestMutation {
			try await self.referencesUseCase.fetch(
				remote: remoteName,
				at: repositoryURL
			)
		}
	}

	func didRequestPush(remoteName: String? = nil) {
		guard let repositoryURL else { return }
		guard pushAction != .unavailable else { return }
		requestMutation {
			try await self.referencesUseCase.push(
				currentBranch: self.currentBranch,
				remotes: self.remotes,
				operationState: self.operationState,
				selectedRemoteName: remoteName,
				at: repositoryURL
			)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL else { return }
		automaticRefreshTask?.cancel()
		refreshTask?.cancel()
		refreshTask = Task {
			isLoading = true
			defer { isLoading = false }

			do {
				let snapshot = try await operation()
				automaticRefreshTask?.cancel()
				try apply(snapshot, at: expectedRepositoryURL)
				automaticRefreshTask?.cancel()
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	private func requestDiffLineMutation(
		_ operation: @escaping @MainActor () async throws -> [WorkingTreeChange]
	) {
		guard
			selectedChangeIDs.count == 1,
			let originalSelection = selectedChangeIDs.first,
			let originalSource = selectedDiffSource
		else { return }

		automaticRefreshTask?.cancel()
		refreshTask?.cancel()
		diffTask?.cancel()
		refreshTask = Task {
			isApplyingDiffLine = true
			defer { isApplyingDiffLine = false }

			do {
				let refreshedChanges = try await operation()
				guard let repositoryURL else { return }
				try Task.checkCancellation()

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
					refreshedSelection.count == 1
					? refreshedSelection.first
					: nil
				let refreshedChange = refreshedSelectionValue.flatMap { selection in
					refreshedChanges.first { $0.id == selection.changeID }
				}
				let refreshedDiff: String
				if let refreshedChange, let refreshedSelectionValue {
					refreshedDiff = try await changesUseCase.loadDiff(
						for: refreshedChange,
						source: refreshedSelectionValue.isStaged ? .staged : .unstaged,
						at: repositoryURL
					)
				} else {
					refreshedDiff = ""
				}
				try Task.checkCancellation()

				changes = refreshedChanges
				selectedChangeIDs = refreshedSelection
				if diff != refreshedDiff {
					diff = refreshedDiff
				}
				displayedDiffSelection = refreshedSelectionValue
				requestedDiffSelection = nil
				if originalSelection != refreshedSelectionValue {
					clearDiffLoad()
				}
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	private func requestAllContent(at repositoryURL: URL) async throws {
		let content = try await contentUseCase.loadSnapshot(at: repositoryURL)
		try apply(content, at: repositoryURL)
	}

	private func apply(_ content: RepositorySnapshot, at repositoryURL: URL?) throws {
		try Task.checkCancellation()
		guard self.repositoryURL == repositoryURL else { throw CancellationError() }

		let changesDidChange =
			self.changes != content.changes || self.amendChanges != content.amendChanges
		if changesDidChange {
			diffTask?.cancel()
			displayedDiffSelection = nil
			requestedDiffSelection = nil
			isLoadingDiff = false
		}
		if self.changes != content.changes {
			self.changes = content.changes
		}
		if self.amendChanges != content.amendChanges {
			self.amendChanges = content.amendChanges
		}
		if commitGraphItems.map(\.commit) != content.commits {
			commitGraphItems = CommitGraphLayoutBuilder.build(commits: content.commits)
		}
		if self.branches != content.branches {
			self.branches = content.branches
		}
		if self.remotes != content.remotes {
			self.remotes = content.remotes
		}
		if self.operationState != content.operationState {
			self.operationState = content.operationState
		}
		if self.tags != content.tags {
			self.tags = content.tags
		}
		if self.stashes != content.stashes {
			self.stashes = content.stashes
		}
		if self.fileTree != content.fileTree {
			self.fileTree = content.fileTree
		}
		preserveSelections()
	}

	private func preserveSelections() {
		preserveChangeSelection()
		if commitGraphItems.isEmpty {
			isAmendingCommit = false
		}
		if commitGraphItems.contains(where: { $0.id == selectedCommitID }) == false {
			selectedCommitID = commitGraphItems.first?.id
			selectedCommitFileID = nil
		}
		didChangeSelectedCommit()
		if branches.contains(where: { $0.id == selectedBranchID }) == false {
			selectedBranchID = branches.first(where: \.isCurrent)?.id ?? branches.first?.id
		}
		if remotes.contains(where: { $0.id == selectedRemoteID }) == false {
			selectedRemoteID = remotes.first?.id
		}
		if stashes.contains(where: { $0.id == selectedStashID }) == false {
			selectedStashID = stashes.first?.id
		}
		if selectedTreeNodeID != nil {
			didSelectTreeNode(requestTreeNode(id: selectedTreeNodeID, in: fileTree))
		}
	}

	private func preserveChangeSelection() {
		var availableSelections = availableWorkingTreeSelections(in: displayedWorkingTreeChanges)
		if isAmendingCommit {
			availableSelections.formUnion(
				amendChanges.map { WorkspaceChangeSelection.amend($0.id) }
			)
		}
		selectedChangeIDs.formIntersection(availableSelections)
		if selectedChangeIDs.isEmpty,
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
		if diff != requestedDiff {
			diff = requestedDiff
		}
		displayedDiffSelection = selection
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
		if !diff.isEmpty {
			diff = ""
		}
		displayedDiffSelection = nil
		clearDiffLoad()
	}

	private func clearDisplayedCommitDiff() {
		if !selectedCommitFiles.isEmpty {
			selectedCommitFiles = []
		}
		selectedCommitFileID = nil
		displayedCommitDiffID = nil
		requestedCommitDiffID = nil
		isLoadingCommitDiff = false
	}

	private var currentCommit: GitCommit? {
		commitGraphItems.first {
			$0.commit.references.contains { reference in
				reference == "HEAD" || reference.hasPrefix("HEAD -> ")
			}
		}?.commit ?? commitGraphItems.first?.commit
	}

	private var filteredWorkingTreeChanges: [WorkingTreeChange] {
		displayedWorkingTreeChanges.filter { matchesChangeFilter(path: $0.path) }
	}

	private func matchesChangeFilter(path: String) -> Bool {
		let query = changeFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return true }
		return path.localizedCaseInsensitiveContains(query)
	}

	private func preserveSelectedCommitFile() {
		guard !selectedCommitFiles.isEmpty else {
			selectedCommitFileID = nil
			return
		}
		guard selectedCommitFiles.contains(where: { $0.id == selectedCommitFileID }) else {
			selectedCommitFileID = selectedCommitFiles.first?.id
			return
		}
	}

	private func requestTreeNode(
		id: String?,
		in nodes: [RepositoryTreeNode]
	) -> RepositoryTreeNode? {
		guard let id else { return nil }

		for node in nodes {
			if node.id == id {
				return node
			}
			if let match = requestTreeNode(id: id, in: node.children) {
				return match
			}
		}

		return nil
	}
}
