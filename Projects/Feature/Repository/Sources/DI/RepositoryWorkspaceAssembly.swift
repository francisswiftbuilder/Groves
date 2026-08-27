import DomainGitInterface
import FeatureRepositoryInterface
import Foundation

@MainActor
final class RepositoryWorkspaceAssembly {
	private let dependencies: RepositoryWorkspaceAssemblyDependencies

	init(dependencies: RepositoryWorkspaceAssemblyDependencies) {
		self.dependencies = dependencies
	}

	func makeWorkspace(repositoryURL: URL?) -> RepositoryWorkspace {
		let diffPreferences = WorkspaceDiffPreferences()
		let output = RepositoryWorkspaceOutput()
		let changesViewModel = ChangesViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				changesUseCase: dependencies.changesUseCase,
				operationsUseCase: dependencies.operationsUseCase,
				externalEditorOpener: dependencies.externalEditorOpener,
				preferences: diffPreferences,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didRequestConfirmation: { confirmation in
					output.workspaceViewModel?.pendingRepositoryConfirmation = confirmation
				}
			)
		)
		let operationViewModel = RepositoryOperationViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				referencesUseCase: dependencies.referencesUseCase,
				operationsUseCase: dependencies.operationsUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didRequestConfirmation: { confirmation in
					output.workspaceViewModel?.pendingRepositoryConfirmation = confirmation
				},
				didRequestViewConflicts: { conflict in
					output.workspaceViewModel?.didViewConflict(conflict)
				}
			)
		)
		let treeViewModel = RepositoryTreeViewModel(
			dependencies: .init(contentUseCase: dependencies.contentUseCase)
		)
		let historyViewModel = HistoryViewModel(
			dependencies: .init(
				changesUseCase: dependencies.changesUseCase,
				preferences: diffPreferences,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didSelectSection: { section in
					output.workspaceViewModel?.didSelectSection(section)
				},
				didFocusBranch: { [weak operationViewModel] branch in
					operationViewModel?.selectedBranchID = branch.id
				},
				didFocusRemoteBranch: { [weak operationViewModel] branch in
					operationViewModel?.selectedRemoteID = branch.remoteName
				}
			)
		)
		let stashesViewModel = StashesViewModel(
			dependencies: .init(
				useCase: dependencies.stashesUseCase,
				preferences: diffPreferences,
				repositoryURL: { output.workspaceViewModel?.repositoryURL },
				hasChanges: { [weak changesViewModel] in
					changesViewModel?.changes.isEmpty == false
				}
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didRequestDropConfirmation: { stash in
					output.workspaceViewModel?.pendingRepositoryConfirmation = .dropStash(stash)
				}
			)
		)
		let viewModel = WorkspaceViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				canAutomaticallyRefresh: { [weak changesViewModel, weak operationViewModel] in
					guard let changesViewModel, let operationViewModel else { return false }
					return !changesViewModel.isLoading
						&& !operationViewModel.isLoading
						&& !changesViewModel.isApplyingDiffLine
				}
			),
			actions: .init(
				resetContent: {
					[
						weak changesViewModel, weak historyViewModel, weak operationViewModel,
						weak stashesViewModel, weak treeViewModel
					] in
					changesViewModel?.reset()
					historyViewModel?.reset()
					operationViewModel?.reset()
					stashesViewModel?.reset()
					treeViewModel?.reset()
				},
				distributeSnapshot: {
					[
						weak changesViewModel, weak historyViewModel, weak operationViewModel,
						weak stashesViewModel, weak treeViewModel
					]
					snapshot,
					repositoryURL in
					changesViewModel?.apply(snapshot)
					historyViewModel?.apply(snapshot)
					operationViewModel?.apply(snapshot)
					stashesViewModel?.apply(snapshot)
					treeViewModel?.apply(snapshot, repositoryURL: repositoryURL)
				},
				confirmRepositoryAction: {
					[weak changesViewModel, weak operationViewModel, weak stashesViewModel]
					confirmation in
					switch confirmation {
					case .discard(let changes):
						changesViewModel?.didConfirmDiscard(changes)
					case .discardHunk(let selection, let change, let options):
						changesViewModel?.didConfirmDiscardHunk(
							selection,
							change: change,
							options: options
						)
					case .markConflictResolved(let conflict):
						changesViewModel?.didConfirmMarkConflictResolved(conflict)
					case .dropStash(let stash):
						stashesViewModel?.didConfirmDrop(stash)
					case .deleteBranch, .deleteTag, .forcePush, .operation, .hardReset,
						.checkoutCommit, .deleteRemote, .deleteRemoteBranch:
						operationViewModel?.didConfirm(confirmation)
					}
				},
				refreshDiffPresentation: {
					[weak changesViewModel, weak historyViewModel, weak stashesViewModel] in
					changesViewModel?.didChangeDiffOptions()
					historyViewModel?.didChangeDiffOptions()
					if let selectedStashID = stashesViewModel?.selectedStashID {
						stashesViewModel?.didSelectStash(selectedStashID)
					}
				},
				focusConflict: { [weak changesViewModel] conflict in
					await changesViewModel?.didSelectChanges([.conflict(conflict.path)])
				},
				activateSidebarSelection: {
					[weak historyViewModel, weak operationViewModel, weak stashesViewModel]
					selection in
					switch selection {
					case .section:
						break
					case .branch(_, let id):
						guard
							let branch = operationViewModel?.branches.first(where: { $0.id == id })
						else { return }
						historyViewModel?.didOpenBranch(branch)
					case .remote(_, let id):
						operationViewModel?.selectedRemoteID = id
					case .remoteBranch(_, let id):
						guard
							let branch = operationViewModel?.remoteBranches.first(where: { $0.id == id })
						else { return }
						historyViewModel?.didOpenRemoteBranch(branch)
					case .tag(_, let id):
						guard let tag = operationViewModel?.tags.first(where: { $0.id == id }) else {
							return
						}
						historyViewModel?.didOpenTag(tag)
					case .stash(_, let id):
						stashesViewModel?.selectedStashID = id
					}
				}
			),
			repositoryURL: repositoryURL
		)
		output.workspaceViewModel = viewModel
		return RepositoryWorkspace(
			viewModel: viewModel,
			changesViewModel: changesViewModel,
			historyViewModel: historyViewModel,
			operationViewModel: operationViewModel,
			stashesViewModel: stashesViewModel,
			treeViewModel: treeViewModel,
			diffPreferences: diffPreferences
		)
	}
}
