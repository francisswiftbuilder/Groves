import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

struct HistoryFocusRequest: Equatable {
	let commitID: String
	let isAnimated: Bool
	private let token = UUID()
}

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
		diffTask?.cancel()
		commitDiffTask?.cancel()
		filePreviewTask?.cancel()
	}

	var repositoryName: String {
		repositoryURL?.lastPathComponent ?? "No Repository"
	}

	var currentBranchName: String {
		branches.first(where: \.isCurrent)?.name ?? "No Branch"
	}

	var selectedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains(.workingTree($0.id)) }
	}

	var selectedStageableChanges: [WorkingTreeChange] {
		selectedChanges.filter(\.hasWorkingTreeChange)
	}

	var displayedWorkingTreeChanges: [WorkingTreeChange] {
		guard isAmendingCommit else { return changes }
		return changes.filter(\.hasWorkingTreeChange)
	}

	var selectedChange: WorkingTreeChange? {
		guard selectedChangeIDs.count == 1 else { return nil }
		return selectedChanges.first
	}

	var selectedAmendChanges: [GitAmendChange] {
		amendChanges.filter { selectedChangeIDs.contains(.amend($0.id)) }
	}

	var selectedAmendChange: GitAmendChange? {
		guard selectedChangeIDs.count == 1 else { return nil }
		return selectedAmendChanges.first
	}

	var selectedDiffLineAction: GitDiffLineAction? {
		guard let selectedChange else { return nil }
		if selectedChange.hasWorkingTreeChange,
			selectedChange.workingTreeState == .modified
		{
			return .stage
		}
		if !selectedChange.hasWorkingTreeChange,
			selectedChange.indexState == .modified
		{
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

	func monitorWorkingTreeChanges() async {
		guard let repositoryURL else { return }

		let events = RepositoryFileSystemMonitor.events(at: repositoryURL)
		do {
			try await refreshWorkingTreeChangesIfNeeded()
		} catch is CancellationError {
			return
		} catch {}

		var automaticRefreshTask: Task<Void, Never>?
		defer {
			automaticRefreshTask?.cancel()
		}

		for await _ in events {
			guard !Task.isCancelled else { return }
			automaticRefreshTask?.cancel()
			automaticRefreshTask = Task { @MainActor [weak self] in
				do {
					try await Task.sleep(for: .milliseconds(350))
					try await self?.refreshWorkingTreeChangesIfNeeded()
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

		if displayedDiffSelection != selection {
			clearDisplayedDiff()
		}
		switch selection {
		case .workingTree(let id):
			guard let change = changes.first(where: { $0.id == id }) else {
				clearDisplayedDiff()
				return
			}
			requestedDiffSelection = selection
			isLoadingDiff = true
			diffTask = Task {
				defer { finishDiffLoad(for: selection) }
				do {
					let requestedDiff = try await repository.requestDiff(for: change, at: repositoryURL)
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

	func didRequestPush() {
		guard let repositoryURL else { return }
		requestMutation {
			try await self.repository.requestPush(at: repositoryURL)
		}
	}

	private func requestMutation(_ operation: @escaping @MainActor () async throws -> Void) {
		refreshTask?.cancel()
		refreshTask = Task {
			isLoading = true
			defer { isLoading = false }

			do {
				try await operation()
				if let repositoryURL {
					try await requestAllContent(at: repositoryURL)
				}
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

				let availableSelections = Set(
					refreshedChanges.map { WorkspaceChangeSelection.workingTree($0.id) }
				)
				var refreshedSelection = selectedChangeIDs.intersection(availableSelections)
				if refreshedSelection.isEmpty, let firstChangeID = refreshedChanges.first?.id {
					refreshedSelection = [.workingTree(firstChangeID)]
				}

				let refreshedChange =
					refreshedSelection.count == 1
					? refreshedChanges.first {
						refreshedSelection.contains(.workingTree($0.id))
					}
					: nil
				let refreshedDiff: String
				if let refreshedChange {
					refreshedDiff = try await repository.requestDiff(
						for: refreshedChange,
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
				displayedDiffSelection = refreshedChange.map {
					.workingTree($0.id)
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
		async let tags = repository.requestTags(at: repositoryURL)
		async let stashes = repository.requestStashes(at: repositoryURL)
		async let fileTree = repository.requestFileTree(at: repositoryURL)

		let content = try await (
			changes,
			amendChanges,
			commits,
			branches,
			remotes,
			tags,
			stashes,
			fileTree
		)
		self.changes = content.0
		self.amendChanges = content.1
		commitGraphItems = CommitGraphLayoutBuilder.build(commits: content.2)
		self.branches = content.3
		self.remotes = content.4
		self.tags = content.5
		self.stashes = content.6
		self.fileTree = content.7
		preserveSelections()
	}

	private func refreshWorkingTreeChangesIfNeeded() async throws {
		guard let repositoryURL, !isLoading, !isApplyingDiffLine else { return }

		let refreshedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		let refreshedAmendChanges =
			isAmendingCommit
			? try await repository.requestAmendChanges(at: repositoryURL)
			: amendChanges
		try Task.checkCancellation()
		guard refreshedChanges != changes || refreshedAmendChanges != amendChanges else { return }

		changes = refreshedChanges
		amendChanges = refreshedAmendChanges
		preserveChangeSelection()
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
		var availableSelections = Set(
			displayedWorkingTreeChanges.map { WorkspaceChangeSelection.workingTree($0.id) }
		)
		if isAmendingCommit {
			availableSelections.formUnion(
				amendChanges.map { WorkspaceChangeSelection.amend($0.id) }
			)
		}
		selectedChangeIDs.formIntersection(availableSelections)
		if selectedChangeIDs.isEmpty, let firstChangeID = displayedWorkingTreeChanges.first?.id {
			selectedChangeIDs = [.workingTree(firstChangeID)]
		} else if selectedChangeIDs.isEmpty,
			isAmendingCommit,
			let firstChangeID = amendChanges.first?.id
		{
			selectedChangeIDs = [.amend(firstChangeID)]
		}
		didChangeSelectedChanges()
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

enum WorkspaceChangeSelection: Hashable {
	case workingTree(String)
	case amend(String)
}

enum RepositoryFilePreview: Equatable, Sendable {
	case none
	case loading
	case text(content: String, byteCount: Int)
	case image(data: Data)
	case unsupported(byteCount: Int)
	case failure(String)

	private static let maximumTextByteCount = 2 * 1_024 * 1_024

	var byteCount: Int? {
		switch self {
		case .text(_, let byteCount), .unsupported(let byteCount):
			return byteCount
		case .image(let data):
			return data.count
		case .none, .loading, .failure:
			return nil
		}
	}

	static func make(path: String, data: Data) -> RepositoryFilePreview {
		let pathExtension = URL(fileURLWithPath: path).pathExtension
		if UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true {
			return .image(data: data)
		}

		guard
			data.count <= maximumTextByteCount,
			!data.contains(0),
			let content = String(data: data, encoding: .utf8)
		else {
			return .unsupported(byteCount: data.count)
		}

		return .text(content: content, byteCount: data.count)
	}
}
