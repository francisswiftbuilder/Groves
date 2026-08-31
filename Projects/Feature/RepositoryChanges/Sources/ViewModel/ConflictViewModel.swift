import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class ConflictViewModel: ObservableObject {
	@Published private(set) var content: GitConflictContent?
	@Published private(set) var isLoadingContent = false
	@Published public private(set) var isLoading = false
	@Published var pendingConfirmation: ConflictConfirmation?
	@Published private(set) var operationState: RepositoryOperationState = .normal

	private let dependencies: ConflictViewModelDependencies
	private let actions: ConflictViewModelActions
	private var selectedConflict: GitConflict?
	private var activeContentRequestID: Int?
	private var contentRequestSequence = 0
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0
	private var contentTask: Task<Void, Never>?
	private var mutationTask: Task<Void, Never>?

	public init(
		dependencies: ConflictViewModelDependencies,
		actions: ConflictViewModelActions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	deinit {
		contentTask?.cancel()
		mutationTask?.cancel()
	}

	var currentLabel: String {
		switch operationState.operation?.kind {
		case .rebase: return "Target Branch"
		case .cherryPick, .revert: return "Current Branch"
		case .merge, .none: return "Current"
		}
	}

	var incomingLabel: String {
		switch operationState.operation?.kind {
		case .rebase: return "Replayed Commit"
		case .cherryPick: return "Picked Commit"
		case .revert: return "Reverted Result"
		case .merge, .none: return "Incoming"
		}
	}

	var oursResolutionLabel: String {
		"Resolve Entire File Using \(currentLabel)"
	}

	var theirsResolutionLabel: String {
		"Resolve Entire File Using \(incomingLabel)"
	}

	public func apply(
		_ snapshot: RepositorySnapshot,
		revalidatesSelectedContent: Bool = true
	) {
		if operationState != snapshot.operationState {
			operationState = snapshot.operationState
		}
		guard let selectedConflict else { return }
		guard
			let refreshedConflict = snapshot.operationState.conflicts.first(where: {
				$0.id == selectedConflict.id
			})
		else {
			didSelectConflict(nil)
			return
		}
		didSelectConflict(
			refreshedConflict,
			forceReload: revalidatesSelectedContent || refreshedConflict != selectedConflict
		)
	}

	public func reset() {
		contentTask?.cancel()
		mutationTask?.cancel()
		contentTask = nil
		mutationTask = nil
		selectedConflict = nil
		activeContentRequestID = nil
		activeMutationRequestID = nil
		content = nil
		isLoadingContent = false
		isLoading = false
		pendingConfirmation = nil
		operationState = .normal
	}

	public func didSelectConflict(_ conflict: GitConflict?, forceReload: Bool = false) {
		let didChangeSelection = selectedConflict?.id != conflict?.id
		guard forceReload || didChangeSelection else { return }
		contentTask?.cancel()
		selectedConflict = conflict
		if didChangeSelection {
			content = nil
		}
		activeContentRequestID = nil
		isLoadingContent = false
		guard let conflict, let repositoryURL = dependencies.repositoryURL() else { return }
		contentRequestSequence += 1
		let requestID = contentRequestSequence
		activeContentRequestID = requestID
		contentTask = Task {
			isLoadingContent = true
			defer {
				if activeContentRequestID == requestID {
					activeContentRequestID = nil
					isLoadingContent = false
				}
			}
			do {
				let loadedContent = try await dependencies.operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				guard activeContentRequestID == requestID else { return }
				if content != loadedContent {
					content = loadedContent
				}
			} catch is CancellationError {
				return
			} catch {
				guard activeContentRequestID == requestID else { return }
			}
		}
	}

	func didResolve(_ conflict: GitConflict, using resolution: GitConflictResolution) {
		guard let repositoryURL = dependencies.repositoryURL() else { return }
		requestMutation {
			try await self.dependencies.operationsUseCase.resolve(
				conflict,
				using: resolution,
				at: repositoryURL
			)
		}
	}

	func didResolve(
		_ hunk: GitConflictHunk,
		in conflict: GitConflict,
		using resolution: GitConflictHunkResolution
	) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!isLoadingContent,
			!isLoading
		else { return }
		mutationTask?.cancel()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				guard let self else { return }
				let snapshot = try await dependencies.operationsUseCase.resolveHunk(
					hunk,
					in: conflict,
					using: resolution,
					at: repositoryURL
				)
				let refreshedContent = try await dependencies.operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				guard activeMutationRequestID == requestID else { return }
				if selectedConflict == conflict, content != refreshedContent {
					content = refreshedContent
				}
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, activeMutationRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: repositoryURL
				) {
					guard activeMutationRequestID == requestID else { return }
					actions.didProduceSnapshot(snapshot)
				}
			}
		}
	}

	func didMarkResolved(_ conflict: GitConflict) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			!isLoadingContent,
			!isLoading
		else { return }
		mutationTask?.cancel()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				guard let self else { return }
				let loadedContent = try await dependencies.operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				guard activeMutationRequestID == requestID else { return }
				if selectedConflict == conflict, content != loadedContent {
					content = loadedContent
				}
				if loadedContent.hasConflictMarkers {
					pendingConfirmation = .markResolved(conflict)
					return
				}
				let snapshot = try await dependencies.operationsUseCase.markResolved(
					path: conflict.path,
					at: repositoryURL
				)
				guard activeMutationRequestID == requestID else { return }
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, activeMutationRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
			}
		}
	}

	func didOpenInEditor(_ conflict: GitConflict) {
		guard
			let repositoryURL = dependencies.repositoryURL(),
			let openExternalEditor = dependencies.openExternalEditor
		else { return }
		let fileURL = repositoryURL.appending(path: conflict.path)
		guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
		do {
			let storedBundleIdentifier = UserDefaults.standard.string(
				forKey: "externalEditorBundleIdentifier"
			)
			try openExternalEditor(
				fileURL,
				storedBundleIdentifier?.isEmpty == false ? storedBundleIdentifier : nil
			)
		} catch {
			actions.didReceiveError(
				"The selected editor is unavailable. Choose another app in Settings."
			)
		}
	}

	func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	func didConfirmPendingConfirmation() {
		guard
			case .markResolved(let conflict) = pendingConfirmation,
			let repositoryURL = dependencies.repositoryURL(),
			!isLoadingContent,
			!isLoading
		else { return }
		pendingConfirmation = nil
		requestMutation {
			try await self.dependencies.operationsUseCase.markResolved(
				path: conflict.path,
				at: repositoryURL
			)
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard
			!isLoadingContent,
			!isLoading,
			let expectedRepositoryURL = dependencies.repositoryURL()
		else { return }
		mutationTask?.cancel()
		let requestID = beginMutation()
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				let snapshot = try await operation()
				guard let self, activeMutationRequestID == requestID else { return }
				actions.didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard let self, activeMutationRequestID == requestID else { return }
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: expectedRepositoryURL
				) {
					guard activeMutationRequestID == requestID else { return }
					actions.didProduceSnapshot(snapshot)
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
}
