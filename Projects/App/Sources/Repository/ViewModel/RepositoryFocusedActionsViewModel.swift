import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
final class RepositoryFocusedActionsViewModel {
	typealias VoidAction = () -> Void

	struct Actions {
		let refresh: VoidAction
		let newBranch: VoidAction
		let fetchAll: VoidAction
		let pull: VoidAction
		let push: (String?) -> Void
		let stageSelectedChanges: VoidAction
		let unstageSelectedChanges: VoidAction
		let stageAllChanges: VoidAction
		let unstageAllChanges: VoidAction
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
			newBranch: @escaping VoidAction,
			fetchAll: @escaping VoidAction,
			pull: @escaping VoidAction,
			push: @escaping (String?) -> Void,
			stageSelectedChanges: @escaping VoidAction,
			unstageSelectedChanges: @escaping VoidAction,
			stageAllChanges: @escaping VoidAction,
			unstageAllChanges: @escaping VoidAction,
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
			self.newBranch = newBranch
			self.fetchAll = fetchAll
			self.pull = pull
			self.push = push
			self.stageSelectedChanges = stageSelectedChanges
			self.unstageSelectedChanges = unstageSelectedChanges
			self.stageAllChanges = stageAllChanges
			self.unstageAllChanges = unstageAllChanges
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
		let operationState: @MainActor () -> RepositoryOperationState
		let canCreateBranch: @MainActor () -> Bool
		let canFetch: @MainActor () -> Bool
		let canPull: @MainActor () -> Bool
		let canPush: @MainActor () -> Bool
		let pushRemoteNames: @MainActor () -> [String]
		let canStageSelection: @MainActor () -> Bool
		let canUnstageSelection: @MainActor () -> Bool
		let canStageAllChanges: @MainActor () -> Bool
		let canUnstageAllChanges: @MainActor () -> Bool
		let selectedBranch: @MainActor () -> GitBranch?
		let selectedCommit: @MainActor () -> GitCommit?
		let selectedRemote: @MainActor () -> GitRemote?

		init(
			operationState: @escaping @MainActor () -> RepositoryOperationState,
			canCreateBranch: @escaping @MainActor () -> Bool,
			canFetch: @escaping @MainActor () -> Bool,
			canPull: @escaping @MainActor () -> Bool,
			canPush: @escaping @MainActor () -> Bool,
			pushRemoteNames: @escaping @MainActor () -> [String],
			canStageSelection: @escaping @MainActor () -> Bool,
			canUnstageSelection: @escaping @MainActor () -> Bool,
			canStageAllChanges: @escaping @MainActor () -> Bool,
			canUnstageAllChanges: @escaping @MainActor () -> Bool,
			selectedBranch: @escaping @MainActor () -> GitBranch?,
			selectedCommit: @escaping @MainActor () -> GitCommit?,
			selectedRemote: @escaping @MainActor () -> GitRemote?
		) {
			self.operationState = operationState
			self.canCreateBranch = canCreateBranch
			self.canFetch = canFetch
			self.canPull = canPull
			self.canPush = canPush
			self.pushRemoteNames = pushRemoteNames
			self.canStageSelection = canStageSelection
			self.canUnstageSelection = canUnstageSelection
			self.canStageAllChanges = canStageAllChanges
			self.canUnstageAllChanges = canUnstageAllChanges
			self.selectedBranch = selectedBranch
			self.selectedCommit = selectedCommit
			self.selectedRemote = selectedRemote
		}
	}

	var focusedActions: RepositoryFocusedActions {
		Self.makeFocusedActions(dependencies: dependencies, actions: actions)
	}

	private let dependencies: Dependencies
	private let actions: Actions

	init(dependencies: Dependencies, actions: Actions) {
		self.dependencies = dependencies
		self.actions = actions
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
		let pushRemoteNames = dependencies.pushRemoteNames()
		let push: VoidAction?
		let pushToRemote: ((String) -> Void)?
		if dependencies.canPush() {
			if pushRemoteNames.isEmpty {
				push = { actions.push(nil) }
				pushToRemote = nil
			} else {
				push = nil
				pushToRemote = { actions.push($0) }
			}
		} else {
			push = nil
			pushToRemote = nil
		}
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
			newBranch: dependencies.canCreateBranch() ? actions.newBranch : nil,
			fetchAll: dependencies.canFetch() ? actions.fetchAll : nil,
			pull: dependencies.canPull() ? actions.pull : nil,
			push: push,
			pushRemoteNames: pushRemoteNames,
			pushToRemote: pushToRemote,
			stageSelectedChanges: dependencies.canStageSelection() ? actions.stageSelectedChanges : nil,
			unstageSelectedChanges: dependencies.canUnstageSelection()
				? actions.unstageSelectedChanges : nil,
			stageAllChanges: dependencies.canStageAllChanges() ? actions.stageAllChanges : nil,
			unstageAllChanges: dependencies.canUnstageAllChanges() ? actions.unstageAllChanges : nil,
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
