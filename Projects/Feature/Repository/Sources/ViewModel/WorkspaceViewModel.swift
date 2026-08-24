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
	@Published var commitSubject = ""
	@Published var commitBody = ""
	@Published private(set) var isAmendingCommit = false
	@Published var newBranchName = ""
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

	private let repository: any GitRepository
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

	init(repository: any GitRepository, repositoryURL: URL? = nil) {
		self.repository = repository
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
		guard let currentBranch, operationState != .detachedHead else { return .unavailable }
		if currentBranch.upstream != nil {
			return .upstream
		}
		let remoteNames = remotes.map(\.name)
		switch remoteNames.count {
		case 0:
			return .unavailable
		case 1:
			return .setUpstream(remoteName: remoteNames[0], branchName: currentBranch.name)
		default:
			return .chooseRemote(remoteNames: remoteNames, branchName: currentBranch.name)
		}
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

	func didChooseRepository(_ url: URL) {
		refreshTask?.cancel()
		let loadID = beginContentLoad()
		refreshTask = Task {
			defer { finishContentLoad(id: loadID) }

			do {
				let root = try await repository.requestRepositoryRoot(at: url)
				if repositoryURL != root {
					diffTask?.cancel()
					commitDiffTask?.cancel()
					selectedChangeIDs = []
					selectedCommitID = nil
					clearDisplayedDiff()
					clearDisplayedCommitDiff()
				}
				repositoryURL = root
				try await requestAllContent(at: root)
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
					let requestedDiff = try await repository.requestDiff(
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
					let requestedDiff = try await repository.requestAmendDiff(
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
				let requestedDiff = try await repository.requestCommitDiff(
					for: commit,
					at: repositoryURL
				)
				let requestedFiles = await Task.detached(priority: .userInitiated) {
					CommitDiffFileParser.parse(requestedDiff)
				}.value
				guard selectedCommitID == commit.id else { return }
				selectedCommitFiles = requestedFiles
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
				let data = try await repository.requestFileContents(
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
			for change in stageableChanges {
				try await self.repository.requestStage(path: change.path, at: repositoryURL)
			}
		}
	}

	func didRequestUnstage(_ requestedChanges: [WorkingTreeChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let stagedChanges = changes.filter {
			requestedIDs.contains($0.id) && $0.isStaged
		}
		guard let repositoryURL, !stagedChanges.isEmpty else { return }
		requestMutation {
			for change in stagedChanges {
				try await self.repository.requestUnstage(path: change.path, at: repositoryURL)
			}
		}
	}

	func didRequestUnstageFromAmend(_ requestedChanges: [GitAmendChange]) {
		let requestedIDs = Set(requestedChanges.map(\.id))
		let amendChanges = amendChanges.filter { requestedIDs.contains($0.id) }
		guard let repositoryURL, !amendChanges.isEmpty else { return }
		requestMutation {
			for change in amendChanges {
				try await self.repository.requestUnstageFromAmend(
					change: change,
					at: repositoryURL
				)
			}
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
			try await self.repository.requestApplyDiffLine(
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
			for change in discardableChanges {
				try await self.repository.requestDiscard(change: change, at: repositoryURL)
			}
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
			try await self.repository.requestCommit(
				subject: subject,
				body: body,
				amend: amend,
				at: repositoryURL
			)
			self.commitSubject = ""
			self.commitBody = ""
			self.isAmendingCommit = false
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
			try await self.repository.requestSwitchBranch(named: branch.name, at: repositoryURL)
		}
	}

	func didRequestCreateBranch() {
		guard let repositoryURL else { return }
		let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		requestMutation {
			try await self.repository.requestCreateBranch(named: name, at: repositoryURL)
			self.newBranchName = ""
		}
	}

	func didRequestCreateLocalBranch(from remoteBranch: GitRemoteBranch) {
		guard
			let repositoryURL,
			!branches.contains(where: { $0.name == remoteBranch.name })
		else { return }
		requestMutation {
			try await self.repository.requestCreateTrackingBranch(
				named: remoteBranch.name,
				tracking: remoteBranch.fullName,
				at: repositoryURL
			)
		}
	}

	func didRequestDeleteBranch() {
		guard let repositoryURL, let branch = selectedBranch, !branch.isCurrent else { return }
		requestMutation {
			try await self.repository.requestDeleteBranch(named: branch.name, at: repositoryURL)
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
		historyFocusRequest = HistoryFocusRequest(commitID: item.id, isAnimated: false)
		selectedSection = .history
	}

	func didRequestCreateStash() {
		guard let repositoryURL, !changes.isEmpty else { return }
		let message = newStashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		requestMutation {
			try await self.repository.requestCreateStash(message: message, at: repositoryURL)
			self.newStashMessage = ""
		}
	}

	func didRequestApplyStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.repository.requestApplyStash(stash, at: repositoryURL)
		}
	}

	func didRequestPopStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.repository.requestPopStash(stash, at: repositoryURL)
		}
	}

	func didRequestDropStash() {
		guard let repositoryURL, let stash = selectedStash else { return }
		requestMutation {
			try await self.repository.requestDropStash(stash, at: repositoryURL)
		}
	}

	func didRequestPull() {
		guard let repositoryURL else { return }
		requestMutation {
			try await self.repository.requestPull(at: repositoryURL)
		}
	}

	func didRequestFetchAll() {
		guard let repositoryURL else { return }
		requestMutation {
			try await self.repository.requestFetchAll(at: repositoryURL)
		}
	}

	func didRequestFetch(remoteName: String) {
		guard let repositoryURL, remotes.contains(where: { $0.name == remoteName }) else { return }
		requestMutation {
			try await self.repository.requestFetch(remote: remoteName, at: repositoryURL)
		}
	}

	func didRequestPush(remoteName: String? = nil) {
		guard let repositoryURL else { return }
		let target: GitPushTarget
		switch pushAction {
		case .unavailable:
			return
		case .upstream:
			target = .upstream
		case .setUpstream(let remoteName, let branchName):
			target = .setUpstream(remoteName: remoteName, branchName: branchName)
		case .chooseRemote(let remoteNames, let branchName):
			guard let remoteName, remoteNames.contains(remoteName) else { return }
			target = .setUpstream(remoteName: remoteName, branchName: branchName)
		}
		requestMutation {
			try await self.repository.requestPush(target, at: repositoryURL)
		}
	}

	private func requestMutation(_ operation: @escaping @MainActor () async throws -> Void) {
		automaticRefreshTask?.cancel()
		refreshTask?.cancel()
		refreshTask = Task {
			isLoading = true
			defer { isLoading = false }

			do {
				try await operation()
				automaticRefreshTask?.cancel()
				if let repositoryURL {
					try await requestAllContent(at: repositoryURL)
				}
				automaticRefreshTask?.cancel()
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	private func requestDiffLineMutation(
		_ operation: @escaping @MainActor () async throws -> Void
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
				try await operation()
				guard let repositoryURL else { return }

				let refreshedChanges = try await repository.requestWorkingTreeChanges(
					at: repositoryURL
				)
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
					refreshedDiff = try await repository.requestDiff(
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
		async let changes = repository.requestWorkingTreeChanges(at: repositoryURL)
		async let amendChanges = repository.requestAmendChanges(at: repositoryURL)
		async let commits = repository.requestCommitHistory(at: repositoryURL)
		async let branches = repository.requestBranches(at: repositoryURL)
		async let remotes = repository.requestRemotes(at: repositoryURL)
		async let operationState = repository.requestOperationState(at: repositoryURL)
		async let tags = repository.requestTags(at: repositoryURL)
		async let stashes = repository.requestStashes(at: repositoryURL)
		async let fileTree = repository.requestFileTree(at: repositoryURL)

		let content = try await (
			changes,
			amendChanges,
			commits,
			branches,
			remotes,
			operationState,
			tags,
			stashes,
			fileTree
		)
		try Task.checkCancellation()
		guard self.repositoryURL == repositoryURL else { throw CancellationError() }

		let changesDidChange = self.changes != content.0 || self.amendChanges != content.1
		if changesDidChange {
			diffTask?.cancel()
			displayedDiffSelection = nil
			requestedDiffSelection = nil
			isLoadingDiff = false
		}
		if self.changes != content.0 {
			self.changes = content.0
		}
		if self.amendChanges != content.1 {
			self.amendChanges = content.1
		}
		if commitGraphItems.map(\.commit) != content.2 {
			commitGraphItems = CommitGraphLayoutBuilder.build(commits: content.2)
		}
		if self.branches != content.3 {
			self.branches = content.3
		}
		if self.remotes != content.4 {
			self.remotes = content.4
		}
		if self.operationState != content.5 {
			self.operationState = content.5
		}
		if self.tags != content.6 {
			self.tags = content.6
		}
		if self.stashes != content.7 {
			self.stashes = content.7
		}
		if self.fileTree != content.8 {
			self.fileTree = content.8
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
