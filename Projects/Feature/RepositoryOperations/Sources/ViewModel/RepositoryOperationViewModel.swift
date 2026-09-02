import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositoryOperationViewModel: ObservableObject {
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

	@Published public private(set) var operationState: RepositoryOperationState = .normal
	@Published public private(set) var isLoading = false
	@Published var pendingMainlineAction: PendingMainlineAction?
	@Published var pendingResetCommit: GitCommit?
	@Published var resetMode: GitResetMode = .mixed
	@Published var pendingConfirmation: RepositoryOperationConfirmation?

	private let dependencies: Dependencies
	private let actions: Actions
	private var changes: [WorkingTreeChange] = []
	private var currentBranch: GitBranch?
	private var mutationTask: Task<Void, Never>?

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
	}

	func cancelTasks() {
		mutationTask?.cancel()
		mutationTask = nil
		isLoading = false
	}

	public func onDisappear() {
		cancelTasks()
	}

	public func didRequestMergeBranch(_ branch: GitBranch) {
		guard let repositoryURL = repositoryURL(), canMergeBranch(branch) else { return }
		requestMutation {
			try await self.referencesUseCase.mergeBranch(named: branch.name, at: repositoryURL)
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
		guard operationState.isIdle, !operationState.isDetached, !isLoading else { return }
		resetMode = .mixed
		pendingResetCommit = commit
	}

	public func didConfirmReset() {
		guard let commit = pendingResetCommit else { return }
		let mode = resetMode
		pendingResetCommit = nil
		if mode == .hard {
			didPresentHardReset(commit)
		} else {
			didRequestReset(commit, mode: mode)
		}
	}

	func didRequestReset(_ commit: GitCommit, mode: GitResetMode) {
		guard
			let repositoryURL = repositoryURL(),
			operationState.isIdle,
			!operationState.isDetached,
			let operationsUseCase
		else { return }
		requestMutation {
			try await operationsUseCase.reset(to: commit.hash, mode: mode, at: repositoryURL)
		}
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
		case .hardReset(let commit):
			didRequestReset(commit, mode: .hard)
		}
	}

	public func didDismissPendingConfirmation() {
		pendingConfirmation = nil
	}

	public func didConfirmPendingConfirmation() {
		guard let confirmation = pendingConfirmation else { return }
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

	func didPresentHardReset(_ commit: GitCommit) {
		guard operationState.isIdle, !operationState.isDetached, !isLoading else { return }
		pendingConfirmation = .hardReset(commit)
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
		_ operation: @escaping @MainActor () async throws -> RepositorySnapshot
	) {
		guard let expectedRepositoryURL = repositoryURL() else { return }
		mutationTask?.cancel()
		mutationTask = Task {
			isLoading = true
			defer { isLoading = false }
			do {
				let snapshot = try await operation()
				try Task.checkCancellation()
				didProduceSnapshot(snapshot)
			} catch is CancellationError {
				return
			} catch {
				didReceiveError(error.localizedDescription)
				await restoreSnapshot(at: expectedRepositoryURL)
			}
		}
	}

	private func restoreSnapshot(at repositoryURL: URL) async {
		if let snapshot = try? await contentUseCase.loadSnapshot(at: repositoryURL) {
			didProduceSnapshot(snapshot)
		}
	}

}
