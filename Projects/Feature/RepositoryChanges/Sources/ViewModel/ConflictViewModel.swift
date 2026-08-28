import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class ConflictViewModel: ObservableObject {
	@Published private(set) var content: GitConflictContent?
	@Published private(set) var isLoadingContent = false
	@Published public private(set) var isLoading = false
	@Published var pendingConfirmation: ConflictConfirmation?

	private let dependencies: ConflictViewModelDependencies
	private let actions: ConflictViewModelActions
	private var operationState: RepositoryOperationState = .normal
	private var selectedConflict: GitConflict?
	private var activeContentRequestID: Int?
	private var contentRequestSequence = 0
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

	public func apply(_ snapshot: RepositorySnapshot) {
		operationState = snapshot.operationState
		guard let selectedConflict else { return }
		guard
			let refreshedConflict = snapshot.operationState.conflicts.first(where: {
				$0.id == selectedConflict.id
			})
		else {
			didSelectConflict(nil)
			return
		}
		didSelectConflict(refreshedConflict, forceReload: true)
	}

	public func reset() {
		contentTask?.cancel()
		mutationTask?.cancel()
		contentTask = nil
		mutationTask = nil
		selectedConflict = nil
		activeContentRequestID = nil
		content = nil
		isLoadingContent = false
		isLoading = false
		pendingConfirmation = nil
		operationState = .normal
	}

	public func didSelectConflict(_ conflict: GitConflict?, forceReload: Bool = false) {
		let didChangeSelection = selectedConflict != conflict
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
				content = loadedContent
			} catch is CancellationError {
				return
			} catch {
				guard activeContentRequestID == requestID else { return }
				content = nil
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
		guard let repositoryURL = dependencies.repositoryURL(), !isLoading else { return }
		requestMutation {
			let snapshot = try await self.dependencies.operationsUseCase.resolveHunk(
				hunk,
				in: conflict,
				using: resolution,
				at: repositoryURL
			)
			let refreshedContent = try await self.dependencies.operationsUseCase.loadConflictContent(
				for: conflict,
				at: repositoryURL
			)
			if self.selectedConflict == conflict {
				self.content = refreshedContent
			}
			return snapshot
		}
	}

	func didMarkResolved(_ conflict: GitConflict) {
		guard let repositoryURL = dependencies.repositoryURL(), !isLoading else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let loadedContent = try await dependencies.operationsUseCase.loadConflictContent(
					for: conflict,
					at: repositoryURL
				)
				if selectedConflict == conflict {
					content = loadedContent
				}
				if loadedContent.hasConflictMarkers {
					pendingConfirmation = .markResolved(conflict)
					return
				}
				actions.didProduceSnapshot(
					try await dependencies.operationsUseCase.markResolved(
						path: conflict.path,
						at: repositoryURL
					)
				)
			} catch is CancellationError {
				return
			} catch {
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
			let repositoryURL = dependencies.repositoryURL()
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
		guard let expectedRepositoryURL = dependencies.repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				actions.didProduceSnapshot(try await operation())
			} catch is CancellationError {
				return
			} catch {
				actions.didReceiveError(error.localizedDescription)
				if let snapshot = try? await dependencies.contentUseCase.loadSnapshot(
					at: expectedRepositoryURL
				) {
					actions.didProduceSnapshot(snapshot)
				}
			}
		}
	}
}
