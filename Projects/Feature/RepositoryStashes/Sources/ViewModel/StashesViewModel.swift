import Combine
import CoreRepositoryDiff
import DomainGitInterface
import Foundation

@MainActor
public final class StashesViewModel: ObservableObject {
	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
		}
	}

	public struct Dependencies {
		public let useCase: any RepositoryStashesUseCase
		public let preferences: WorkspaceDiffPreferences
		public let repositoryURL: @MainActor () -> URL?

		public init(
			useCase: any RepositoryStashesUseCase,
			preferences: WorkspaceDiffPreferences,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.useCase = useCase
			self.preferences = preferences
			self.repositoryURL = repositoryURL
		}
	}

	@Published public private(set) var selectedStashID: String?
	@Published public private(set) var selectedFileID: CommitDiffFile.ID?
	@Published var newStashMessage = ""
	@Published var includeUntrackedInStash = true
	@Published public private(set) var stashes: [GitStash] = []
	@Published private(set) var files: [CommitDiffFile] = []
	@Published private(set) var diff = ""
	@Published private(set) var imageDiff: GitImageDiff?
	@Published private(set) var isLoadingDiff = false
	@Published private(set) var isLoadingImageDiff = false
	@Published private(set) var isLoading = false
	@Published private(set) var hasChanges = false
	@Published var pendingDrop: GitStash?

	private let dependencies: Dependencies
	private let actions: Actions
	private var mutationTask: Task<Void, Never>?
	private var diffTask: Task<Void, Never>?
	private var imageDiffTask: Task<Void, Never>?
	private var activeDiffRequest: StashDiffRequest?
	private var activeImageDiffRequest: StashImageDiffRequest?
	private var displayedStashID: String?
	private var requestSequence = 0

	public init(
		dependencies: Dependencies,
		actions: Actions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	private var useCase: any RepositoryStashesUseCase {
		dependencies.useCase
	}

	private var preferences: WorkspaceDiffPreferences {
		dependencies.preferences
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

	deinit {
		mutationTask?.cancel()
		diffTask?.cancel()
		imageDiffTask?.cancel()
	}

	var selectedStash: GitStash? {
		stashes.first { $0.id == selectedStashID }
	}

	var selectedFile: CommitDiffFile? {
		files.first { $0.id == selectedFileID }
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		let snapshotHasChanges = snapshot.changes.isEmpty == false
		if hasChanges != snapshotHasChanges {
			hasChanges = snapshotHasChanges
		}
		if stashes != snapshot.stashes {
			stashes = snapshot.stashes
		}
		let keepsSelection = stashes.contains { $0.id == selectedStashID }
		guard keepsSelection == false else { return }
		guard selectedStashID != nil || stashes.isEmpty == false else { return }
		didSelectStash(stashes.first?.id)
	}

	public func reset() {
		mutationTask?.cancel()
		diffTask?.cancel()
		imageDiffTask?.cancel()
		activeDiffRequest = nil
		activeImageDiffRequest = nil
		selectedStashID = nil
		newStashMessage = ""
		stashes = []
		isLoading = false
		hasChanges = false
		clearDiffState()
	}

	public func onAppear() {
		guard !isLoadingDiff else { return }
		if let selectedStash, displayedStashID != selectedStash.id {
			requestDiff()
		} else if let selectedFile,
			DiffImageFileSupport.isSupported(path: selectedFile.path),
			imageDiff == nil,
			!isLoadingImageDiff
		{
			requestImageDiff()
		}
	}

	public func onDisappear() {
		mutationTask?.cancel()
		diffTask?.cancel()
		imageDiffTask?.cancel()
		mutationTask = nil
		diffTask = nil
		imageDiffTask = nil
		activeDiffRequest = nil
		activeImageDiffRequest = nil
		isLoading = false
		isLoadingDiff = false
		isLoadingImageDiff = false
	}

	public func didChangeWorkingTreeState(hasChanges: Bool) {
		self.hasChanges = hasChanges
	}

	func didRequestCreateStash() {
		guard let repositoryURL = repositoryURL(), hasChanges else { return }
		let message = newStashMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		requestMutation {
			let snapshot = try await self.useCase.createStash(
				message: message,
				includeUntracked: self.includeUntrackedInStash,
				at: repositoryURL
			)
			self.newStashMessage = ""
			return snapshot
		}
	}

	public func didRequestApplyStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		requestMutation {
			try await self.useCase.applyStash(stash, at: repositoryURL)
		}
	}

	public func didSelectStash(_ stashID: String?) {
		selectedStashID = stashID
		clearDiffState()
		requestDiff()
	}

	public func didSelectFile(_ fileID: CommitDiffFile.ID?) {
		guard selectedFileID != fileID else { return }
		selectedFileID = fileID
		requestImageDiff()
	}

	public func didChangeDiffOptions() {
		requestDiff()
	}

	private func clearDiffState() {
		diffTask?.cancel()
		imageDiffTask?.cancel()
		activeDiffRequest = nil
		activeImageDiffRequest = nil
		displayedStashID = nil
		selectedFileID = nil
		files = []
		diff = ""
		imageDiff = nil
		isLoadingDiff = false
		isLoadingImageDiff = false
	}

	private func requestDiff() {
		diffTask?.cancel()
		activeDiffRequest = nil
		isLoadingDiff = false
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		requestSequence += 1
		let request = StashDiffRequest(
			id: requestSequence,
			repositoryURL: repositoryURL,
			stashID: stash.id
		)
		activeDiffRequest = request
		let options = preferences.options
		isLoadingDiff = true
		diffTask = Task {
			do {
				let requestedDiff = try await useCase.loadDiff(
					for: stash,
					options: options,
					at: repositoryURL
				)
				let parseWorker = Task.detached(priority: .userInitiated) {
					try CommitDiffFileParser.parseCancellable(requestedDiff)
				}
				let parsedFiles = try await withTaskCancellationHandler {
					try await parseWorker.value
				} onCancel: {
					parseWorker.cancel()
				}
				guard activeDiffRequest == request else { return }
				activeDiffRequest = nil
				isLoadingDiff = false
				diff = requestedDiff
				files = parsedFiles
				displayedStashID = stash.id
				selectedFileID =
					parsedFiles.contains { $0.id == selectedFileID }
					? selectedFileID : parsedFiles.first?.id
				requestImageDiff()
			} catch is CancellationError {
				return
			} catch {
				guard activeDiffRequest == request else { return }
				activeDiffRequest = nil
				isLoadingDiff = false
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func requestImageDiff() {
		imageDiffTask?.cancel()
		activeImageDiffRequest = nil
		imageDiff = nil
		isLoadingImageDiff = false
		guard
			let repositoryURL = repositoryURL(),
			let stash = selectedStash,
			let file = selectedFile,
			DiffImageFileSupport.isSupported(path: file.path)
		else { return }

		requestSequence += 1
		let request = StashImageDiffRequest(
			id: requestSequence,
			repositoryURL: repositoryURL,
			stashID: stash.id,
			fileID: file.id
		)
		activeImageDiffRequest = request
		isLoadingImageDiff = true
		imageDiffTask = Task {
			do {
				let requestedImageDiff = try await useCase.loadImageDiff(
					for: stash,
					path: file.path,
					previousPath: file.previousPath,
					at: repositoryURL
				)
				guard activeImageDiffRequest == request else { return }
				activeImageDiffRequest = nil
				isLoadingImageDiff = false
				imageDiff = requestedImageDiff
			} catch is CancellationError {
				return
			} catch {
				guard activeImageDiffRequest == request else { return }
				activeImageDiffRequest = nil
				isLoadingImageDiff = false
				didReceiveError(error.localizedDescription)
			}
		}
	}

	public func didRequestPopStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		requestMutation {
			try await self.useCase.popStash(stash, at: repositoryURL)
		}
	}

	public func didPresentStashDrop(_ stash: GitStash) {
		guard !isLoading else { return }
		pendingDrop = stash
	}

	func didDismissStashDrop() {
		pendingDrop = nil
	}

	func didConfirmStashDrop() {
		guard let stash = pendingDrop else { return }
		pendingDrop = nil
		didConfirmDrop(stash)
	}

	func didConfirmDrop(_ stash: GitStash) {
		guard let repositoryURL = repositoryURL() else { return }
		requestMutation {
			try await self.useCase.dropStash(stash, at: repositoryURL)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard !isLoading else { return }
		mutationTask?.cancel()
		isLoading = true
		mutationTask = Task {
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				try Task.checkCancellation()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}
}
