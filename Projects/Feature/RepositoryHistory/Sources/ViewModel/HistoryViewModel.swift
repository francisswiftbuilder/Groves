import Combine
import CoreRepositoryDiff
import DomainGitInterface
import Foundation

@MainActor
public final class HistoryViewModel: ObservableObject {
	@Published var selectedCommitID: String?
	@Published var selectedCommitFileID: CommitDiffFile.ID?
	@Published var searchText = ""
	@Published var commitGraphItems: [CommitGraphItem] = []
	@Published var displayedCommitGraphItems: [CommitGraphItem] = []
	@Published var selectedCommitFiles: [CommitDiffFile] = []
	@Published var commitImageDiff: GitImageDiff?
	@Published var historyFocusRequest: HistoryFocusRequest?
	@Published var isLoadingCommitDiff = false
	@Published var isLoadingCommitImageDiff = false
	private var displayedCommitDiffID: String?
	private var requestedCommitDiffID: String?
	private var activeCommitDiffRequestID: Int?
	private var commitDiffRequestSequence = 0
	private var activeCommitImageDiffRequestID: Int?
	private var commitImageDiffRequestSequence = 0
	private var commits: [GitCommit] = []
	private var snapshotRevision = 0
	private var commitDiffTask: Task<Void, Never>?
	private var commitImageDiffTask: Task<Void, Never>?
	private var layoutTask: Task<Void, Never>?
	private var searchTask: Task<Void, Never>?
	private let dependencies: HistoryViewModelDependencies
	private let actions: HistoryViewModelActions

	public init(
		dependencies: HistoryViewModelDependencies,
		actions: HistoryViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	private var changesUseCase: any RepositoryChangesUseCase {
		dependencies.changesUseCase
	}

	private var preferences: WorkspaceDiffPreferences {
		dependencies.preferences
	}

	private var repositoryURL: @MainActor () -> URL? {
		dependencies.repositoryURL
	}

	private var didReceiveError: @MainActor (String) -> Void {
		actions.didReceiveError
	}

	private var didRequestPresentation: @MainActor () -> Void {
		actions.didRequestPresentation
	}

	private var didFocusBranch: @MainActor (GitBranch) -> Void {
		actions.didFocusBranch
	}

	private var didFocusRemoteBranch: @MainActor (GitRemoteBranch) -> Void {
		actions.didFocusRemoteBranch
	}

	deinit {
		commitDiffTask?.cancel()
		commitImageDiffTask?.cancel()
		layoutTask?.cancel()
		searchTask?.cancel()
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		guard commits != snapshot.commits else { return }
		commits = snapshot.commits
		requestLayout()
	}

	func cancelTasks() {
		commitDiffTask?.cancel()
		commitImageDiffTask?.cancel()
		layoutTask?.cancel()
		searchTask?.cancel()
	}

	public func reset() {
		cancelTasks()
		snapshotRevision += 1
		commits = []
		selectedCommitID = nil
		selectedCommitFileID = nil
		commitGraphItems = []
		displayedCommitGraphItems = []
		historyFocusRequest = nil
		clearDisplayedCommitDiff()
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
		didChangeSelectedCommitImageDiff()
	}

	func didChangeSearchText(_ searchText: String) {
		guard searchText != self.searchText else { return }
		self.searchText = searchText
		requestFilter()
	}

	public func didChangeDiffOptions() {
		didChangeSelectedCommit(forceReload: true)
	}

	public func didOpenBranch(_ branch: GitBranch) {
		guard
			let item = commitGraphItems.first(where: {
				$0.commit.shortHash == branch.shortHash || $0.commit.hash.hasPrefix(branch.shortHash)
			})
		else {
			didReceiveError("The latest commit for branch \(branch.name) is not available in History.")
			return
		}

		focus(item)
		didFocusBranch(branch)
	}

	public func didOpenRemoteBranch(_ branch: GitRemoteBranch) {
		guard let item = commitGraphItems.first(where: { $0.commit.hash == branch.hash }) else {
			didReceiveError(
				"The latest commit for remote branch \(branch.fullName) is not available in History."
			)
			return
		}

		focus(item)
		didFocusRemoteBranch(branch)
	}

	public func didOpenTag(_ tag: GitTag) {
		guard let item = commitGraphItems.first(where: { $0.commit.hash == tag.targetHash }) else {
			didReceiveError("The commit for tag \(tag.name) is not available in History.")
			return
		}

		focus(item)
	}

	func didChangeSelectedCommit(forceReload: Bool = false) {
		guard let repositoryURL = repositoryURL(), let commit = selectedCommit else {
			commitDiffTask?.cancel()
			selectedCommitFileID = nil
			clearDisplayedCommitDiff()
			return
		}
		guard
			forceReload
				|| (displayedCommitDiffID != commit.id && requestedCommitDiffID != commit.id)
		else {
			return
		}

		commitDiffTask?.cancel()
		if displayedCommitDiffID != commit.id {
			clearDisplayedCommitDiff()
		}
		requestedCommitDiffID = commit.id
		commitDiffRequestSequence += 1
		let requestID = commitDiffRequestSequence
		activeCommitDiffRequestID = requestID
		isLoadingCommitDiff = true

		commitDiffTask = Task {
			defer {
				if activeCommitDiffRequestID == requestID {
					activeCommitDiffRequestID = nil
					requestedCommitDiffID = nil
					isLoadingCommitDiff = false
				}
			}
			do {
				let requestedDiff = try await changesUseCase.loadCommitDiff(
					for: commit,
					options: preferences.options,
					at: repositoryURL
				)
				let requestedFiles = await Task.detached(priority: .userInitiated) {
					CommitDiffFileParser.parse(requestedDiff)
				}.value
				guard activeCommitDiffRequestID == requestID, selectedCommitID == commit.id else {
					return
				}
				selectedCommitFiles = requestedFiles
				preserveSelectedCommitFile()
				displayedCommitDiffID = commit.id
				didChangeSelectedCommitImageDiff()
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	public var selectedCommit: GitCommit? {
		commitGraphItems.first { $0.id == selectedCommitID }?.commit
	}

	var selectedCommitFile: CommitDiffFile? {
		guard !selectedCommitFiles.isEmpty else { return nil }
		return selectedCommitFiles.first { $0.id == selectedCommitFileID }
			?? selectedCommitFiles.first
	}

	private func requestLayout() {
		layoutTask?.cancel()
		searchTask?.cancel()
		snapshotRevision += 1
		let revision = snapshotRevision
		let requestedCommits = commits
		layoutTask = Task {
			let items = await Task.detached(priority: .userInitiated) {
				CommitGraphLayoutBuilder.build(commits: requestedCommits)
			}.value
			guard Task.isCancelled == false, snapshotRevision == revision else { return }
			commitGraphItems = items
			requestFilter()
			preserveSelection()
		}
	}

	private func requestFilter() {
		searchTask?.cancel()
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let requestedCommits = commits
		let revision = snapshotRevision
		guard !query.isEmpty else {
			displayedCommitGraphItems = commitGraphItems
			return
		}
		searchTask = Task {
			do {
				try await Task.sleep(for: .milliseconds(150))
			} catch {
				return
			}
			let items = await Task.detached(priority: .userInitiated) {
				let filteredCommits = requestedCommits.filter { Self.commit($0, matches: query) }
				return CommitGraphLayoutBuilder.build(commits: filteredCommits)
			}.value
			guard Task.isCancelled == false,
				snapshotRevision == revision,
				searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
			else { return }
			displayedCommitGraphItems = items
			if !items.contains(where: { $0.id == selectedCommitID }) {
				selectedCommitID = items.first?.id
				selectedCommitFileID = nil
				didChangeSelectedCommit()
			}
		}
	}

	private func preserveSelection() {
		if commitGraphItems.contains(where: { $0.id == selectedCommitID }) == false {
			selectedCommitID = commitGraphItems.first?.id
			selectedCommitFileID = nil
		}
		didChangeSelectedCommit()
	}

	private func focus(_ item: CommitGraphItem) {
		clearDisplayedCommitDiff()
		selectedCommitID = item.id
		didChangeSelectedCommit()
		historyFocusRequest = HistoryFocusRequest(commitID: item.id, isAnimated: false)
		didRequestPresentation()
	}

	private func clearDisplayedCommitDiff() {
		if !selectedCommitFiles.isEmpty {
			selectedCommitFiles = []
		}
		selectedCommitFileID = nil
		commitImageDiffTask?.cancel()
		activeCommitImageDiffRequestID = nil
		commitImageDiff = nil
		isLoadingCommitImageDiff = false
		displayedCommitDiffID = nil
		requestedCommitDiffID = nil
		activeCommitDiffRequestID = nil
		isLoadingCommitDiff = false
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

	private func didChangeSelectedCommitImageDiff() {
		commitImageDiffTask?.cancel()
		activeCommitImageDiffRequestID = nil
		commitImageDiff = nil
		isLoadingCommitImageDiff = false
		guard
			let repositoryURL = repositoryURL(),
			let commit = selectedCommit,
			let file = selectedCommitFile,
			DiffImageFileSupport.isSupported(path: file.path)
		else { return }

		commitImageDiffRequestSequence += 1
		let requestID = commitImageDiffRequestSequence
		activeCommitImageDiffRequestID = requestID
		isLoadingCommitImageDiff = true
		commitImageDiffTask = Task {
			defer {
				if activeCommitImageDiffRequestID == requestID {
					activeCommitImageDiffRequestID = nil
					isLoadingCommitImageDiff = false
				}
			}
			do {
				let requestedImageDiff = try await changesUseCase.loadCommitImageDiff(
					for: commit,
					path: file.path,
					previousPath: file.previousPath,
					at: repositoryURL
				)
				guard activeCommitImageDiffRequestID == requestID else { return }
				commitImageDiff = requestedImageDiff
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	nonisolated private static func commit(_ commit: GitCommit, matches query: String) -> Bool {
		[
			commit.subject,
			commit.body,
			commit.author,
			commit.authorEmail,
			commit.committer,
			commit.committerEmail,
			commit.hash,
			commit.shortHash,
			commit.references.joined(separator: " "),
		].contains { value in
			value.localizedCaseInsensitiveContains(query)
		}
	}
}
