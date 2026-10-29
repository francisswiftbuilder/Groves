import CoreRepositoryDiff
import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class StashesViewModel {
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

	public private(set) var selectedStashID: String?
	public private(set) var selectedFileID: CommitDiffFile.ID?
	var newStashMessage = ""
	var includeUntrackedInStash = true
	public private(set) var stashes: [GitStash] = []
	private(set) var files: [CommitDiffFile] = []
	private(set) var diff = ""
	private(set) var imageDiff: GitImageDiff?
	private(set) var isLoadingDiff = false
	private(set) var isLoadingImageDiff = false
	private(set) var isLoading = false
	private(set) var hasChanges = false
	var pendingDrop: StashDropConfirmation?
	private(set) var mutationMessage: String?

	private let dependencies: Dependencies
	private let actions: Actions
	@ObservationIgnored private var mutationTask: Task<Void, Never>?
	@ObservationIgnored private var diffTask: Task<Void, Never>?
	@ObservationIgnored private var imageDiffTask: Task<Void, Never>?
	@ObservationIgnored private var activeDiffRequest: StashDiffRequest?
	@ObservationIgnored private var activeImageDiffRequest: StashImageDiffRequest?
	@ObservationIgnored private var displayedStashHash: String?
	@ObservationIgnored private var activeMutationRequestID: Int?
	@ObservationIgnored private var mutationSequence = 0
	@ObservationIgnored private var requestSequence = 0

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
		let previousSelection = selectedStash
		hasChanges = !snapshot.changes.isEmpty
		stashes = snapshot.stashes
		let selection =
			stashes.first { $0.id == selectedStashID }
			?? previousSelection.flatMap { previous in
				stashes.first { $0.hash == previous.hash && $0.subject == previous.subject }
			}
			?? stashes.first
		if let previousSelection, let selection,
			previousSelection.hash == selection.hash
		{
			selectedStashID = selection.id
			return
		}
		guard selectedStashID != selection?.id else { return }
		didSelectStash(selection?.id)
	}

	public func reset() {
		onDisappear()
		selectedStashID = nil
		newStashMessage = ""
		includeUntrackedInStash = true
		stashes = []
		hasChanges = false
		mutationMessage = nil
		clearDiffState()
	}

	public func onAppear() {
		guard !isLoadingDiff else { return }
		if let selectedStash, displayedStashHash != selectedStash.hash {
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
		activeMutationRequestID = nil
		pendingDrop = nil
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
		let submittedMessage = newStashMessage
		let includeUntracked = includeUntrackedInStash
		let message = submittedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
		let useCase = useCase
		requestMutation {
			try await useCase.createStash(
				message: message, includeUntracked: includeUntracked, at: repositoryURL)
		} didSucceed: { [weak self] in
			guard let self, self.newStashMessage == submittedMessage,
				self.includeUntrackedInStash == includeUntracked
			else { return }
			self.newStashMessage = ""
		}
	}

	public func didRequestApplyStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		let useCase = useCase
		requestMutation {
			try await useCase.applyStash(stash, at: repositoryURL)
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
		displayedStashHash = nil
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
			id: requestSequence, repositoryURL: repositoryURL, stashHash: stash.hash)
		activeDiffRequest = request
		let options = preferences.options
		let useCase = useCase
		isLoadingDiff = true
		diffTask = Task { [weak self] in
			defer { self?.finishDiff(request) }
			do {
				let requestedDiff = try await useCase.loadDiff(
					for: stash, options: options, at: repositoryURL)
				try Task.checkCancellation()
				let parseWorker = Task.detached(priority: .userInitiated) {
					try CommitDiffFileParser.parseCancellable(requestedDiff)
				}
				let parsedFiles = try await withTaskCancellationHandler {
					try await parseWorker.value
				} onCancel: {
					parseWorker.cancel()
				}
				try Task.checkCancellation()
				guard let self, self.activeDiffRequest == request,
					self.repositoryURL() == repositoryURL, self.selectedStash?.hash == stash.hash
				else { return }
				diff = requestedDiff
				files = parsedFiles
				displayedStashHash = stash.hash
				selectedFileID =
					parsedFiles.contains { $0.id == selectedFileID }
					? selectedFileID : parsedFiles.first?.id
				requestImageDiff()
			} catch is CancellationError { return } catch {
				guard let self, !Task.isCancelled, self.activeDiffRequest == request,
					self.repositoryURL() == repositoryURL
				else { return }
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func finishDiff(_ request: StashDiffRequest) {
		guard activeDiffRequest == request else { return }
		activeDiffRequest = nil
		diffTask = nil
		isLoadingDiff = false
	}

	private func requestImageDiff() {
		imageDiffTask?.cancel()
		activeImageDiffRequest = nil
		imageDiff = nil
		isLoadingImageDiff = false
		guard let repositoryURL = repositoryURL(), let stash = selectedStash,
			let file = selectedFile, DiffImageFileSupport.isSupported(path: file.path)
		else { return }
		requestSequence += 1
		let request = StashImageDiffRequest(
			id: requestSequence, repositoryURL: repositoryURL,
			stashHash: stash.hash, fileID: file.id)
		activeImageDiffRequest = request
		let useCase = useCase
		isLoadingImageDiff = true
		imageDiffTask = Task { [weak self] in
			defer { self?.finishImageDiff(request) }
			do {
				let requested = try await useCase.loadImageDiff(
					for: stash, path: file.path,
					previousPath: file.previousPath, at: repositoryURL)
				try Task.checkCancellation()
				guard let self, self.activeImageDiffRequest == request,
					self.repositoryURL() == repositoryURL, self.selectedStash?.hash == stash.hash
				else { return }
				imageDiff = requested
			} catch is CancellationError { return } catch {
				guard let self, !Task.isCancelled, self.activeImageDiffRequest == request,
					self.repositoryURL() == repositoryURL
				else { return }
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func finishImageDiff(_ request: StashImageDiffRequest) {
		guard activeImageDiffRequest == request else { return }
		activeImageDiffRequest = nil
		imageDiffTask = nil
		isLoadingImageDiff = false
	}

	public func didRequestPopStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		let useCase = useCase
		requestMutation { try await useCase.popStash(stash, at: repositoryURL) }
	}

	public func didPresentStashDrop(_ stash: GitStash) {
		guard !isLoading, let repositoryURL = repositoryURL() else { return }
		pendingDrop = StashDropConfirmation(stash: stash, repositoryURL: repositoryURL)
	}

	func didDismissStashDrop() { pendingDrop = nil }

	func didConfirmStashDrop() {
		guard !isLoading, let confirmation = pendingDrop else { return }
		pendingDrop = nil
		guard repositoryURL() == confirmation.repositoryURL,
			stashes.contains(where: {
				$0.hash == confirmation.stash.hash && $0.subject == confirmation.stash.subject
			})
		else {
			didReceiveError("The repository or stash list has changed. Select the stash again.")
			return
		}
		let useCase = useCase
		requestMutation {
			try await useCase.dropStash(confirmation.stash, at: confirmation.repositoryURL)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositoryStashMutationResult,
		didSucceed: @escaping @MainActor () -> Void = {}
	) {
		guard !isLoading, let expectedRepositoryURL = repositoryURL() else { return }
		mutationSequence += 1
		let requestID = mutationSequence
		activeMutationRequestID = requestID
		isLoading = true
		mutationMessage = nil
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				try Task.checkCancellation()
				let result = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeMutationRequestID == requestID,
					self.repositoryURL() == expectedRepositoryURL
				else { return }
				if result.outcome == .completed { didSucceed() }
				didProduceSnapshot(result.snapshot)
				switch result.outcome {
				case .completed: break
				case .nothingToSave:
					mutationMessage = "No changes matched the stash options. Your message has been kept."
				case .conflicted:
					mutationMessage = "The changes have conflicts. The stash was kept for recovery."
				case .failed(let message):
					mutationMessage = message
					didReceiveError(message)
				}
			} catch is CancellationError { return } catch {
				guard let self, !Task.isCancelled, self.activeMutationRequestID == requestID,
					self.repositoryURL() == expectedRepositoryURL
				else { return }
				mutationMessage = error.localizedDescription
				didReceiveError(error.localizedDescription)
			}
		}
	}

	private func finishMutation(id: Int) {
		guard activeMutationRequestID == id else { return }
		activeMutationRequestID = nil
		mutationTask = nil
		isLoading = false
	}
}
