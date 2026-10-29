import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class RepositoryOperationViewModel {
	public struct Actions {
		public let didProduceSnapshot: @MainActor (RepositorySnapshot) -> Void
		public let didReceiveError: @MainActor (String) -> Void
		public let didRequestViewConflicts: @MainActor (GitConflict) -> Void

		public init(
			didProduceSnapshot: @escaping @MainActor (RepositorySnapshot) -> Void,
			didReceiveError: @escaping @MainActor (String) -> Void,
			didRequestViewConflicts: @escaping @MainActor (GitConflict) -> Void
		) {
			self.didProduceSnapshot = didProduceSnapshot
			self.didReceiveError = didReceiveError
			self.didRequestViewConflicts = didRequestViewConflicts
		}
	}

	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase
		public let referencesUseCase: any RepositoryReferencesUseCase
		public let operationsUseCase: (any RepositoryOperationsUseCase)?
		public let repositoryURL: @MainActor () -> URL?

		public init(
			contentUseCase: any RepositoryContentUseCase,
			referencesUseCase: any RepositoryReferencesUseCase,
			operationsUseCase: (any RepositoryOperationsUseCase)?,
			repositoryURL: @escaping @MainActor () -> URL?
		) {
			self.contentUseCase = contentUseCase
			self.referencesUseCase = referencesUseCase
			self.operationsUseCase = operationsUseCase
			self.repositoryURL = repositoryURL
		}
	}

	public private(set) var operationState: RepositoryOperationState = .normal
	public private(set) var isLoading = false
	var pendingMainlineAction: PendingMainlineAction?
	var pendingReset: RepositoryResetPresentation?
	var resetMode: GitResetMode = .mixed
	var pendingConfirmation: RepositoryOperationConfirmation?
	private(set) var mutationErrorMessage: String?

	private let dependencies: Dependencies
	private let actions: Actions
	private var changes: [WorkingTreeChange] = []
	private var currentBranch: GitBranch?
	@ObservationIgnored private var mutationTask: Task<Void, Never>?
	private var activeMutationRequestID: Int?
	private var mutationRequestSequence = 0

	public init(
		dependencies: Dependencies,
		actions: Actions
	) {
		self.dependencies = dependencies
		self.actions = actions
	}

	private var contentUseCase: any RepositoryContentUseCase {
		dependencies.contentUseCase
	}

	private var referencesUseCase: any RepositoryReferencesUseCase {
		dependencies.referencesUseCase
	}

	private var operationsUseCase: (any RepositoryOperationsUseCase)? {
		dependencies.operationsUseCase
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

	private var didRequestViewConflicts: @MainActor (GitConflict) -> Void {
		actions.didRequestViewConflicts
	}

	deinit {
		mutationTask?.cancel()
	}

	var conflicts: [GitConflict] {
		operationState.conflicts
	}

	public func canMergeBranch(_ branch: GitBranch) -> Bool {
		currentBranch != nil
			&& !branch.isCurrent
			&& operationState.isIdle
			&& !operationState.isDetached
			&& !isLoading
	}

	public func canRebaseOnto(_ branch: GitBranch) -> Bool {
		canMergeBranch(branch) && changes.isEmpty
	}

	public func apply(_ snapshot: RepositorySnapshot) {
		currentBranch = snapshot.branches.first(where: \.isCurrent)
		if operationState != snapshot.operationState {
			operationState = snapshot.operationState
		}
		changes = snapshot.changes
	}

	public func reset() {
		cancelTasks()
		currentBranch = nil
		changes = []
		operationState = .normal
		pendingMainlineAction = nil
		pendingReset = nil
		pendingConfirmation = nil
		resetMode = .mixed
		mutationErrorMessage = nil
	}

	func cancelTasks() {
		mutationTask?.cancel()
		mutationTask = nil
		activeMutationRequestID = nil
		isLoading = false
	}

	public func onDisappear() {
		cancelTasks()
		pendingReset = nil
		pendingConfirmation = nil
		pendingMainlineAction = nil
	}

	public func didRequestMergeBranch(_ branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), canMergeBranch(branch) else { return }
		let referencesUseCase = referencesUseCase
		requestMutation {
			try await referencesUseCase.mergeBranch(named: branch.name, at: repositoryURL)
		}
	}

	public func didRequestRebase(onto branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), canRebaseOnto(branch), let operationsUseCase else {
			return
		}
		requestMutation {
			try await operationsUseCase.rebase(onto: branch.name, at: repositoryURL)
		}
	}

	func didRequestCherryPick(_ commit: GitCommit, mainline: Int? = nil) {
		didPerformCommitAction(.cherryPick(commit), mainline: mainline)
	}

	func didRequestRevert(_ commit: GitCommit, mainline: Int? = nil) {
		didPerformCommitAction(.revert(commit), mainline: mainline)
	}

	public func didPresentCherryPick(_ commit: GitCommit) {
		didPresentCommitAction(.cherryPick(commit))
	}

	public func didPresentRevert(_ commit: GitCommit) {
		didPresentCommitAction(.revert(commit))
	}

	func didPresentCommitAction(_ action: PendingMainlineAction) {
		guard !operationState.isDetached else { return }
		if action.commit.parentHashes.count > 1 {
			pendingMainlineAction = action
		} else {
			didPerformCommitAction(action, mainline: nil)
		}
	}

	public func didPerformPendingMainlineAction(parent: Int) {
		guard let action = pendingMainlineAction else { return }
		pendingMainlineAction = nil
		didPerformCommitAction(action, mainline: parent)
	}

	public func didPresentReset(_ commit: GitCommit) {
		guard operationState.isIdle, !operationState.isDetached, !isLoading,
			let repositoryURL = repositoryURL(), let currentBranch
		else { return }
		resetMode = .mixed
		mutationErrorMessage = nil
		pendingReset = RepositoryResetPresentation(
			commit: commit, repositoryURL: repositoryURL,
			context: GitResetContext(branchName: currentBranch.name, headHash: currentBranch.hash))
	}

	public func didConfirmReset() {
		guard !isLoading, let presentation = pendingReset else { return }
		guard validateResetPresentation(presentation) else { return }
		let mode = resetMode
		if mode == .hard {
			pendingReset = nil
			pendingConfirmation = .hardReset(presentation)
		} else {
			requestReset(presentation, mode: mode)
		}
	}

	private func requestReset(_ presentation: RepositoryResetPresentation, mode: GitResetMode) {
		guard
			!isLoading,
			operationState.isIdle,
			!operationState.isDetached,
			let operationsUseCase
		else { return }
		guard validateResetPresentation(presentation) else { return }
		requestMutation {
			try await operationsUseCase.reset(
				to: presentation.commit.hash, mode: mode, expecting: presentation.context,
				at: presentation.repositoryURL)
		} didSucceed: { [weak self] in
			guard self?.pendingReset?.id == presentation.id else { return }
			self?.pendingReset = nil
		}
	}

	private func validateResetPresentation(_ presentation: RepositoryResetPresentation) -> Bool {
		guard repositoryURL() == presentation.repositoryURL,
			currentBranch?.name == presentation.context.branchName,
			currentBranch?.hash == presentation.context.headHash
		else {
			pendingReset = nil
			pendingConfirmation = nil
			didReceiveError(
				"The repository, branch or HEAD has changed. Open Reset again to review the target.")
			return false
		}
		return true
	}

	public func didPerformOperationAction(_ action: RepositoryOperationAction) {
		guard
			let repositoryURL = repositoryURL(),
			let operation = operationState.operation,
			let operationsUseCase,
			action != .continue || conflicts.isEmpty
		else { return }
		requestMutation {
			try await operationsUseCase.perform(action, for: operation.kind, at: repositoryURL)
		}
	}

	public func didPresentOperationAction(_ action: RepositoryOperationAction) {
		guard let operation = operationState.operation, action != .continue else { return }
		pendingConfirmation = .operation(action, operation.kind)
	}

	public func didViewConflicts() {
		guard let conflict = conflicts.first else { return }
		didRequestViewConflicts(conflict)
	}

	func didConfirm(_ confirmation: RepositoryOperationConfirmation) {
		switch confirmation {
		case .operation(let action, let operation):
			requestOperationAction(action, operation: operation)
		case .hardReset(let presentation):
			requestReset(presentation, mode: .hard)
		}
	}

	public func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	public func didConfirmPendingConfirmation() {
		guard !isLoading, let confirmation = pendingConfirmation else { return }
		pendingConfirmation = nil
		didConfirm(confirmation)
	}

	private func requestOperationAction(
		_ action: RepositoryOperationAction,
		operation: RepositoryOperationKind
	) {
		guard
			let repositoryURL = repositoryURL(),
			let operationsUseCase,
			operationState.operation?.kind == operation
		else { return }
		requestMutation {
			try await operationsUseCase.perform(action, for: operation, at: repositoryURL)
		}
	}

	private func didPerformCommitAction(_ action: PendingMainlineAction, mainline: Int?) {
		guard
			let repositoryURL = repositoryURL(),
			operationState.isIdle,
			!operationState.isDetached,
			let operationsUseCase
		else { return }
		requestMutation {
			switch action {
			case .cherryPick(let commit):
				return try await operationsUseCase.cherryPick(
					commitHash: commit.hash,
					mainline: mainline,
					at: repositoryURL
				)
			case .revert(let commit):
				return try await operationsUseCase.revert(
					commitHash: commit.hash,
					mainline: mainline,
					at: repositoryURL
				)
			}
		}
	}

	private func requestMutation(
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot,
		didSucceed: @escaping @MainActor () -> Void = {}
	) {
		guard !isLoading, let expectedRepositoryURL = repositoryURL() else { return }
		mutationRequestSequence += 1
		let requestID = mutationRequestSequence
		activeMutationRequestID = requestID
		isLoading = true
		mutationErrorMessage = nil
		let contentUseCase = contentUseCase
		mutationTask = Task { [weak self] in
			defer { self?.finishMutation(id: requestID) }
			do {
				try Task.checkCancellation()
				let snapshot = try await operation()
				try Task.checkCancellation()
				guard let self, self.activeMutationRequestID == requestID,
					self.repositoryURL() == expectedRepositoryURL
				else { return }
				didSucceed()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				guard !Task.isCancelled, self?.activeMutationRequestID == requestID,
					self?.repositoryURL() == expectedRepositoryURL
				else { return }
				self?.mutationErrorMessage = error.localizedDescription
				self?.didReceiveError(error.localizedDescription)
				if let snapshot = try? await contentUseCase.loadSnapshot(at: expectedRepositoryURL) {
					guard let self, !Task.isCancelled, self.activeMutationRequestID == requestID,
						self.repositoryURL() == expectedRepositoryURL
					else { return }
					didProduceSnapshot(snapshot)
				}
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
