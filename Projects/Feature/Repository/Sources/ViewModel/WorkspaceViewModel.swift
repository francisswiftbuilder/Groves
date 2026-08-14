import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

@MainActor
final class WorkspaceViewModel: ObservableObject {
	@Published var selectedSection: WorkspaceSection? = .changes
	@Published var selectedChangeIDs: Set<String> = []
	@Published var selectedCommitID: String?
	@Published var selectedBranchID: String?
	@Published var selectedTagID: String?
	@Published private(set) var selectedTreeNodeID: String?
	@Published var commitMessage = ""
	@Published var newBranchName = ""
	@Published var newTagName = ""
	@Published var newTagMessage = ""
	@Published private(set) var repositoryURL: URL?
	@Published private(set) var changes: [WorkingTreeChange] = []
	@Published private(set) var commitGraphItems: [CommitGraphItem] = []
	@Published private(set) var branches: [GitBranch] = []
	@Published private(set) var tags: [GitTag] = []
	@Published private(set) var fileTree: [RepositoryTreeNode] = []
	@Published private(set) var diff = ""
	@Published private(set) var filePreview: RepositoryFilePreview = .none
	@Published private(set) var isLoading = false
	@Published private(set) var isApplyingDiffLine = false
	@Published var alertMessage: String?

	private let repository: any GitRepository
	private var refreshTask: Task<Void, Never>?
	private var diffTask: Task<Void, Never>?
	private var filePreviewTask: Task<Void, Never>?

	init(repository: any GitRepository, repositoryURL: URL? = nil) {
		self.repository = repository
		self.repositoryURL = repositoryURL
	}

	deinit {
		refreshTask?.cancel()
		diffTask?.cancel()
		filePreviewTask?.cancel()
	}

	var repositoryName: String {
		repositoryURL?.lastPathComponent ?? "No Repository"
	}

	var currentBranchName: String {
		branches.first(where: \.isCurrent)?.name ?? "No Branch"
	}

	var selectedChanges: [WorkingTreeChange] {
		changes.filter { selectedChangeIDs.contains($0.id) }
	}

	var selectedChange: WorkingTreeChange? {
		guard selectedChangeIDs.count == 1 else { return nil }
		return selectedChanges.first
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

	var selectedTag: GitTag? {
		tags.first { $0.id == selectedTagID }
	}

	var canCommit: Bool {
		!commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& changes.contains(where: \.isStaged)
			&& !isLoading
	}

	func didSelectSection(_ section: WorkspaceSection) {
		selectedSection = section
	}

	func didChooseRepository(_ url: URL) {
		refreshTask?.cancel()
		refreshTask = Task {
			isLoading = true
			defer { isLoading = false }

			do {
				let root = try await repository.requestRepositoryRoot(at: url)
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
		refreshTask = Task {
			isLoading = true
			defer { isLoading = false }

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
		diff = ""

		guard let repositoryURL, let change = selectedChange else { return }
		diffTask = Task {
			do {
				let requestedDiff = try await repository.requestDiff(for: change, at: repositoryURL)
				guard selectedChangeIDs == Set([change.id]) else { return }
				diff = requestedDiff
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
		let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		requestMutation {
			try await self.repository.requestCommit(message: message, at: repositoryURL)
			self.commitMessage = ""
		}
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

	func didRequestCreateTag() {
		guard let repositoryURL else { return }
		let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
		let message = newTagMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty else { return }
		requestMutation {
			try await self.repository.requestCreateTag(named: name, message: message, at: repositoryURL)
			self.newTagName = ""
			self.newTagMessage = ""
		}
	}

	func didRequestDeleteTag() {
		guard let repositoryURL, let tag = selectedTag else { return }
		requestMutation {
			try await self.repository.requestDeleteTag(named: tag.name, at: repositoryURL)
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

				let availableChangeIDs = Set(refreshedChanges.map(\.id))
				var refreshedSelection = selectedChangeIDs.intersection(availableChangeIDs)
				if refreshedSelection.isEmpty, let firstChangeID = refreshedChanges.first?.id {
					refreshedSelection = [firstChangeID]
				}

				let refreshedChange =
					refreshedSelection.count == 1
					? refreshedChanges.first { refreshedSelection.contains($0.id) }
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
				diff = refreshedDiff
			} catch is CancellationError {
				return
			} catch {
				alertMessage = error.localizedDescription
			}
		}
	}

	private func requestAllContent(at repositoryURL: URL) async throws {
		async let changes = repository.requestWorkingTreeChanges(at: repositoryURL)
		async let commits = repository.requestCommitHistory(at: repositoryURL)
		async let branches = repository.requestBranches(at: repositoryURL)
		async let tags = repository.requestTags(at: repositoryURL)
		async let fileTree = repository.requestFileTree(at: repositoryURL)

		let content = try await (changes, commits, branches, tags, fileTree)
		self.changes = content.0
		commitGraphItems = CommitGraphLayoutBuilder.build(commits: content.1)
		self.branches = content.2
		self.tags = content.3
		self.fileTree = content.4
		preserveSelections()
	}

	private func refreshWorkingTreeChangesIfNeeded() async throws {
		guard let repositoryURL, !isLoading, !isApplyingDiffLine else { return }

		let refreshedChanges = try await repository.requestWorkingTreeChanges(at: repositoryURL)
		try Task.checkCancellation()
		guard refreshedChanges != changes else { return }

		changes = refreshedChanges
		preserveChangeSelection()
	}

	private func preserveSelections() {
		preserveChangeSelection()
		if commitGraphItems.contains(where: { $0.id == selectedCommitID }) == false {
			selectedCommitID = commitGraphItems.first?.id
		}
		if branches.contains(where: { $0.id == selectedBranchID }) == false {
			selectedBranchID = branches.first(where: \.isCurrent)?.id ?? branches.first?.id
		}
		if tags.contains(where: { $0.id == selectedTagID }) == false {
			selectedTagID = tags.first?.id
		}
		if selectedTreeNodeID != nil {
			didSelectTreeNode(requestTreeNode(id: selectedTreeNodeID, in: fileTree))
		}
	}

	private func preserveChangeSelection() {
		let availableChangeIDs = Set(changes.map(\.id))
		selectedChangeIDs.formIntersection(availableChangeIDs)
		if selectedChangeIDs.isEmpty, let firstChangeID = changes.first?.id {
			selectedChangeIDs = [firstChangeID]
		}
		didChangeSelectedChanges()
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
