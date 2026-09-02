import Combine
import DomainGitInterface
import Foundation

@MainActor
final class RepositoryFocusedActionsViewModel: ObservableObject {
	typealias VoidAction = () -> Void

	struct Actions {
		let refresh: VoidAction
		let viewConflicts: VoidAction
		let performOperationAction: (RepositoryOperationAction) -> Void
		let presentOperationAction: (RepositoryOperationAction) -> Void
		let rebase: (GitBranch) -> Void
		let renameBranch: (GitBranch) -> Void
		let cherryPick: (GitCommit) -> Void
		let revert: (GitCommit) -> Void
		let reset: (GitCommit) -> Void
		let addRemote: VoidAction
		let renameRemote: (GitRemote) -> Void
		let editRemote: (GitRemote) -> Void
		let deleteRemote: (GitRemote) -> Void

		init(
			refresh: @escaping VoidAction,
			viewConflicts: @escaping VoidAction,
			performOperationAction: @escaping (RepositoryOperationAction) -> Void,
			presentOperationAction: @escaping (RepositoryOperationAction) -> Void,
			rebase: @escaping (GitBranch) -> Void,
			renameBranch: @escaping (GitBranch) -> Void,
			cherryPick: @escaping (GitCommit) -> Void,
			revert: @escaping (GitCommit) -> Void,
			reset: @escaping (GitCommit) -> Void,
			addRemote: @escaping VoidAction,
			renameRemote: @escaping (GitRemote) -> Void,
			editRemote: @escaping (GitRemote) -> Void,
			deleteRemote: @escaping (GitRemote) -> Void
		) {
			self.refresh = refresh
			self.viewConflicts = viewConflicts
			self.performOperationAction = performOperationAction
			self.presentOperationAction = presentOperationAction
			self.rebase = rebase
			self.renameBranch = renameBranch
			self.cherryPick = cherryPick
			self.revert = revert
			self.reset = reset
			self.addRemote = addRemote
			self.renameRemote = renameRemote
			self.editRemote = editRemote
			self.deleteRemote = deleteRemote
		}
	}

	struct Dependencies {
		let stateChanges: AnyPublisher<Void, Never>
		let operationState: @MainActor () -> RepositoryOperationState
		let selectedBranch: @MainActor () -> GitBranch?
		let selectedCommit: @MainActor () -> GitCommit?
		let selectedRemote: @MainActor () -> GitRemote?

		init(
			stateChanges: AnyPublisher<Void, Never>,
			operationState: @escaping @MainActor () -> RepositoryOperationState,
			selectedBranch: @escaping @MainActor () -> GitBranch?,
			selectedCommit: @escaping @MainActor () -> GitCommit?,
			selectedRemote: @escaping @MainActor () -> GitRemote?
		) {
			self.stateChanges = stateChanges
			self.operationState = operationState
			self.selectedBranch = selectedBranch
			self.selectedCommit = selectedCommit
			self.selectedRemote = selectedRemote
		}
	}

	@Published private(set) var focusedActions: RepositoryFocusedActions

	private let dependencies: Dependencies
	private let actions: Actions
	private var stateChangesCancellable: AnyCancellable?

	init(dependencies: Dependencies, actions: Actions) {
		self.dependencies = dependencies
		self.actions = actions
		focusedActions = Self.makeFocusedActions(dependencies: dependencies, actions: actions)
	}

	func onAppear() {
		updateFocusedActions()
		guard stateChangesCancellable == nil else { return }
		stateChangesCancellable = dependencies.stateChanges.sink { [weak self] in
			self?.updateFocusedActions()
		}
	}

	func onDisappear() {
		stateChangesCancellable?.cancel()
		stateChangesCancellable = nil
	}

	private func updateFocusedActions() {
		focusedActions = Self.makeFocusedActions(dependencies: dependencies, actions: actions)
	}

	private static func makeFocusedActions(
		dependencies: Dependencies,
		actions: Actions
	) -> RepositoryFocusedActions {
		let operationState = dependencies.operationState()
		let operation = operationState.operation
		let selectedBranch = dependencies.selectedBranch()
		let selectedCommit = dependencies.selectedCommit()
		let selectedRemote = dependencies.selectedRemote()
		let continueOperation: VoidAction?
		if operation != nil, !operationState.hasConflicts {
			continueOperation = {
				actions.performOperationAction(.continue)
			}
		} else {
			continueOperation = nil
		}
		let skipOperation: VoidAction?
		if operation != nil, operation?.kind != .merge {
			skipOperation = {
				actions.presentOperationAction(.skip)
			}
		} else {
			skipOperation = nil
		}
		let abortOperation: VoidAction?
		if operation != nil {
			abortOperation = {
				actions.presentOperationAction(.abort)
			}
		} else {
			abortOperation = nil
		}
		let rebaseSelectedBranch: VoidAction?
		let renameSelectedBranch: VoidAction?
		if let selectedBranch {
			rebaseSelectedBranch = {
				actions.rebase(selectedBranch)
			}
			renameSelectedBranch = {
				actions.renameBranch(selectedBranch)
			}
		} else {
			rebaseSelectedBranch = nil
			renameSelectedBranch = nil
		}
		let cherryPickSelectedCommit: VoidAction?
		let revertSelectedCommit: VoidAction?
		let resetSelectedCommit: VoidAction?
		if let selectedCommit {
			cherryPickSelectedCommit = {
				actions.cherryPick(selectedCommit)
			}
			revertSelectedCommit = {
				actions.revert(selectedCommit)
			}
			resetSelectedCommit = {
				actions.reset(selectedCommit)
			}
		} else {
			cherryPickSelectedCommit = nil
			revertSelectedCommit = nil
			resetSelectedCommit = nil
		}
		let renameSelectedRemote: VoidAction?
		let editSelectedRemote: VoidAction?
		let deleteSelectedRemote: VoidAction?
		if let selectedRemote {
			renameSelectedRemote = {
				actions.renameRemote(selectedRemote)
			}
			editSelectedRemote = {
				actions.editRemote(selectedRemote)
			}
			deleteSelectedRemote = {
				actions.deleteRemote(selectedRemote)
			}
		} else {
			renameSelectedRemote = nil
			editSelectedRemote = nil
			deleteSelectedRemote = nil
		}
		return RepositoryFocusedActions(
			refresh: actions.refresh,
			viewConflicts: operationState.hasConflicts ? actions.viewConflicts : nil,
			continueOperation: continueOperation,
			skipOperation: skipOperation,
			abortOperation: abortOperation,
			rebaseSelectedBranch: rebaseSelectedBranch,
			renameSelectedBranch: renameSelectedBranch,
			cherryPickSelectedCommit: cherryPickSelectedCommit,
			revertSelectedCommit: revertSelectedCommit,
			resetSelectedCommit: resetSelectedCommit,
			addRemote: actions.addRemote,
			renameSelectedRemote: renameSelectedRemote,
			editSelectedRemote: editSelectedRemote,
			deleteSelectedRemote: deleteSelectedRemote
		)
	}
}
