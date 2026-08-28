import Combine
import CoreRepositoryDiff
import DomainGitInterface
import Foundation

@MainActor
final class StashesViewModel: ObservableObject {
	@Published var selectedStashID: String?
	@Published var newStashMessage = ""
	@Published var includeUntrackedInStash = true
	@Published private(set) var stashes: [GitStash] = []
	@Published private(set) var diff = ""
	@Published private(set) var imageDiff: GitImageDiff?
	@Published private(set) var isLoadingImageDiff = false
	@Published private(set) var isLoading = false
	@Published private(set) var hasChanges = false
	@Published var pendingDrop: GitStash?

	private let dependencies: StashesViewModelDependencies
	private let actions: StashesViewModelActions
	private var mutationTask: Task<Void, Never>?
	private var diffTask: Task<Void, Never>?
	private var imageDiffTask: Task<Void, Never>?
	private var activeDiffRequestID: Int?
	private var diffRequestSequence = 0

	init(
		dependencies: StashesViewModelDependencies,
		actions: StashesViewModelActions
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

	func apply(_ snapshot: RepositorySnapshot) {
		hasChanges = snapshot.changes.isEmpty == false
		if stashes != snapshot.stashes {
			stashes = snapshot.stashes
		}
		if stashes.contains(where: { $0.id == selectedStashID }) == false {
			selectedStashID = stashes.first?.id
		}
	}

	func reset() {
		mutationTask?.cancel()
		diffTask?.cancel()
		imageDiffTask?.cancel()
		activeDiffRequestID = nil
		selectedStashID = nil
		newStashMessage = ""
		stashes = []
		diff = ""
		imageDiff = nil
		isLoadingImageDiff = false
		isLoading = false
		hasChanges = false
	}

	func didChangeWorkingTreeState(hasChanges: Bool) {
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

	func didRequestApplyStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		requestMutation {
			try await self.useCase.applyStash(stash, at: repositoryURL)
		}
	}

	func didSelectStash(_ stashID: String?) {
		selectedStashID = stashID
		diff = ""
		imageDiffTask?.cancel()
		imageDiff = nil
		isLoadingImageDiff = false
		requestDiff()
	}

	func didChangeDiffOptions() {
		requestDiff()
	}

	private func requestDiff() {
		diffTask?.cancel()
		activeDiffRequestID = nil
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		diffRequestSequence += 1
		let requestID = diffRequestSequence
		activeDiffRequestID = requestID
		diffTask = Task {
			do {
				let requestedDiff = try await useCase.loadDiff(
					for: stash,
					options: preferences.options,
					at: repositoryURL
				)
				guard activeDiffRequestID == requestID else { return }
				activeDiffRequestID = nil
				diff = requestedDiff
			} catch is CancellationError {
				return
			} catch {
				guard activeDiffRequestID == requestID else { return }
				activeDiffRequestID = nil
				didReceiveError(error.localizedDescription)
			}
		}
	}

	func didSelectStashFile(_ file: CommitDiffFile?) {
		imageDiffTask?.cancel()
		imageDiff = nil
		isLoadingImageDiff = false
		guard
			let repositoryURL = repositoryURL(),
			let stash = selectedStash,
			let file,
			DiffImageFileSupport.isSupported(path: file.path)
		else { return }

		isLoadingImageDiff = true
		imageDiffTask = Task {
			defer { isLoadingImageDiff = false }
			do {
				let requestedImageDiff = try await useCase.loadImageDiff(
					for: stash,
					path: file.path,
					previousPath: file.previousPath,
					at: repositoryURL
				)
				guard selectedStashID == stash.id else { return }
				imageDiff = requestedImageDiff
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
			}
		}
	}

	func didRequestPopStash() {
		guard let repositoryURL = repositoryURL(), let stash = selectedStash else { return }
		requestMutation {
			try await self.useCase.popStash(stash, at: repositoryURL)
		}
	}

	func didPresentStashDrop(_ stash: GitStash) {
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
