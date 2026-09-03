import Combine
import CoreRepositoryDiff
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import FeatureRepositoryTree
import Foundation

@MainActor
final class RepositoryWorkspaceAssembly {
	private let dependencies: RepositoryWorkspaceAssemblyDependencies

	init(dependencies: RepositoryWorkspaceAssemblyDependencies) {
		self.dependencies = dependencies
	}

	func makeWorkspace(repositoryURL: URL?) -> RepositoryWorkspace {
		let diffPreferences = WorkspaceDiffPreferences()
		let changesDiffSearchViewModel = RepositorySearchViewModel()
		let historyDiffSearchViewModel = RepositorySearchViewModel()
		let stashesDiffSearchViewModel = RepositorySearchViewModel()
		let output = RepositoryWorkspaceOutput()
		let openExternalEditor: (@MainActor (URL, String?) throws -> Void)?
		if let opener = dependencies.externalEditorOpener {
			openExternalEditor = { fileURL, applicationBundleIdentifier in
				try opener.openFile(
					at: fileURL,
					applicationBundleIdentifier: applicationBundleIdentifier
				)
			}
		} else {
			openExternalEditor = nil
		}
		let changesViewModel = ChangesViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				changesUseCase: dependencies.changesUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didSelectConflict: { conflict in
					output.conflictViewModel?.didSelectConflict(conflict)
				},
				didSelectDiff: { selection, forceReload in
					output.changesDiffViewModel?.didSelect(selection, forceReload: forceReload)
				}
			)
		)
		let changesDiffViewModel = ChangesDiffViewModel(
			dependencies: .init(
				changesUseCase: dependencies.changesUseCase,
				preferences: diffPreferences,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didApplyMutation: { refreshedChanges, originalChange, source in
					output.changesViewModel?.didApplyDiffMutation(
						refreshedChanges,
						replacing: originalChange,
						source: source
					)
					output.stashesViewModel?.didChangeWorkingTreeState(
						hasChanges: output.changesViewModel?.changes.isEmpty == false
					)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		output.changesViewModel = changesViewModel
		output.changesDiffViewModel = changesDiffViewModel
		let conflictViewModel = ConflictViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				operationsUseCase: dependencies.operationsUseCase,
				openExternalEditor: openExternalEditor,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		output.conflictViewModel = conflictViewModel
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
				didRequestViewConflicts: { conflict in
					output.workspaceViewModel?.didViewConflict(conflict)
				}
			)
		)
		let referencesViewModel = RepositoryReferencesViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				referencesUseCase: dependencies.referencesUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		let syncViewModel = RepositorySyncViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				referencesUseCase: dependencies.referencesUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		let remotesViewModel = RemotesViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				referencesUseCase: dependencies.referencesUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		let commitViewModel = CommitViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				changesUseCase: dependencies.changesUseCase,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				},
				didChangeAmendingCommit: { [weak changesViewModel] isAmending in
					changesViewModel?.didSetAmendingCommit(isAmending)
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
				didRequestPresentation: {
					output.workspaceViewModel?.didSelectSection(.history)
				},
				didFocusBranch: { [weak referencesViewModel] branch in
					referencesViewModel?.selectedBranchID = branch.id
				},
				didFocusRemoteBranch: { [weak remotesViewModel] branch in
					remotesViewModel?.selectedRemoteID = branch.remoteName
				}
			)
		)
		let stashesViewModel = StashesViewModel(
			dependencies: .init(
				useCase: dependencies.stashesUseCase,
				preferences: diffPreferences,
				repositoryURL: { output.workspaceViewModel?.repositoryURL }
			),
			actions: .init(
				didProduceSnapshot: { snapshot in
					output.workspaceViewModel?.didProduceSnapshot(snapshot)
				},
				didReceiveError: { message in
					output.workspaceViewModel?.alertMessage = message
				}
			)
		)
		output.stashesViewModel = stashesViewModel
		let viewModel = WorkspaceViewModel(
			dependencies: .init(
				contentUseCase: dependencies.contentUseCase,
				canAutomaticallyRefresh: {
					[
						weak changesViewModel, weak changesDiffViewModel,
						weak commitViewModel, weak conflictViewModel,
						weak operationViewModel,
						weak referencesViewModel, weak syncViewModel, weak remotesViewModel,
					] in
					guard
						let changesViewModel,
						let changesDiffViewModel,
						let commitViewModel,
						let conflictViewModel,
						let operationViewModel,
						let referencesViewModel,
						let syncViewModel,
						let remotesViewModel
					else {
						return false
					}
					return !changesViewModel.isLoading
						&& !changesDiffViewModel.isLoading
						&& !changesDiffViewModel.isApplyingAction
						&& !commitViewModel.isLoading
						&& !conflictViewModel.isLoading
						&& !operationViewModel.isLoading
						&& !referencesViewModel.isLoading
						&& !syncViewModel.isLoading
						&& !remotesViewModel.isLoading
				}
			),
			actions: .init(
				resetContent: {
					[
						weak changesViewModel, weak changesDiffViewModel,
						weak commitViewModel, weak conflictViewModel,
						weak historyViewModel,
						weak operationViewModel, weak referencesViewModel, weak syncViewModel,
						weak remotesViewModel,
						weak stashesViewModel, weak treeViewModel
					] in
					changesViewModel?.reset()
					changesDiffViewModel?.reset()
					commitViewModel?.reset()
					conflictViewModel?.reset()
					historyViewModel?.reset()
					operationViewModel?.reset()
					referencesViewModel?.reset()
					syncViewModel?.reset()
					remotesViewModel?.reset()
					stashesViewModel?.reset()
					treeViewModel?.reset()
				},
				distributeSnapshot: {
					[
						weak changesViewModel, weak commitViewModel, weak conflictViewModel,
						weak historyViewModel,
						weak operationViewModel, weak referencesViewModel, weak syncViewModel,
						weak remotesViewModel,
						weak stashesViewModel, weak treeViewModel
					]
					snapshot,
					repositoryURL,
					revalidatesSelectedContent in
					conflictViewModel?.apply(
						snapshot,
						revalidatesSelectedContent: revalidatesSelectedContent
					)
					changesViewModel?.apply(
						snapshot,
						revalidatesSelectedDiff: revalidatesSelectedContent
					)
					commitViewModel?.apply(snapshot)
					historyViewModel?.apply(snapshot)
					operationViewModel?.apply(snapshot)
					referencesViewModel?.apply(snapshot)
					syncViewModel?.apply(snapshot)
					remotesViewModel?.apply(snapshot)
					stashesViewModel?.apply(snapshot)
					treeViewModel?.apply(snapshot, repositoryURL: repositoryURL)
				},
				refreshDiffPresentation: {
					[weak changesDiffViewModel, weak historyViewModel, weak stashesViewModel] in
					changesDiffViewModel?.didChangeDiffOptions()
					historyViewModel?.didChangeDiffOptions()
					stashesViewModel?.didChangeDiffOptions()
				},
				focusConflict: { [weak changesViewModel] conflict in
					await changesViewModel?.didSelectChanges([.conflict(conflict.path)])
				},
				activateSidebarSelection: {
					[
						weak historyViewModel, weak referencesViewModel,
						weak remotesViewModel,
						weak stashesViewModel,
					]
					selection in
					switch selection {
					case .section:
						break
					case .branch(_, let id):
						guard
							let branch = referencesViewModel?.branches.first(where: { $0.id == id })
						else { return }
						historyViewModel?.didOpenBranch(branch)
					case .remote(_, let id):
						remotesViewModel?.selectedRemoteID = id
					case .remoteBranch(_, let id):
						guard
							let branch = remotesViewModel?.remoteBranches.first(where: { $0.id == id })
						else { return }
						historyViewModel?.didOpenRemoteBranch(branch)
					case .tag(_, let id):
						guard let tag = referencesViewModel?.tags.first(where: { $0.id == id }) else {
							return
						}
						historyViewModel?.didOpenTag(tag)
					case .stash(_, let id):
						stashesViewModel?.didSelectStash(id)
					}
				}
			),
			repositoryURL: repositoryURL
		)
		output.workspaceViewModel = viewModel
		let commitActions = RepositoryCommitActions(
			cherryPick: operationViewModel.didPresentCherryPick,
			revert: operationViewModel.didPresentRevert,
			createBranch: referencesViewModel.didPresentNewBranch,
			checkoutCommit: referencesViewModel.didPresentCheckoutCommit,
			createTag: referencesViewModel.didPresentNewTag,
			reset: operationViewModel.didPresentReset
		)
		let focusedActionsStateChanges = Publishers.MergeMany(
			operationViewModel.$operationState.map { _ in () }.eraseToAnyPublisher(),
			historyViewModel.selectedCommitIDChanges,
			referencesViewModel.$selectedBranchID.map { _ in () }.eraseToAnyPublisher(),
			referencesViewModel.$branches.map { _ in () }.eraseToAnyPublisher(),
			remotesViewModel.$selectedRemoteID.map { _ in () }.eraseToAnyPublisher(),
			remotesViewModel.$remotes.map { _ in () }.eraseToAnyPublisher()
		)
		.eraseToAnyPublisher()
		let focusedActionsViewModel = RepositoryFocusedActionsViewModel(
			dependencies: .init(
				stateChanges: focusedActionsStateChanges,
				operationState: { operationViewModel.operationState },
				selectedBranch: { referencesViewModel.selectedBranch },
				selectedCommit: { historyViewModel.selectedCommit },
				selectedRemote: { remotesViewModel.selectedRemote }
			),
			actions: .init(
				refresh: viewModel.didRequestRefresh,
				viewConflicts: operationViewModel.didViewConflicts,
				performOperationAction: operationViewModel.didPerformOperationAction,
				presentOperationAction: operationViewModel.didPresentOperationAction,
				rebase: operationViewModel.didRequestRebase,
				renameBranch: referencesViewModel.didPresentBranchRename,
				cherryPick: operationViewModel.didPresentCherryPick,
				revert: operationViewModel.didPresentRevert,
				reset: operationViewModel.didPresentReset,
				addRemote: remotesViewModel.didPresentAddRemote,
				renameRemote: remotesViewModel.didPresentRename,
				editRemote: remotesViewModel.didPresentEditor,
				deleteRemote: remotesViewModel.didPresentDeletion
			)
		)
		return RepositoryWorkspace(
			viewModel: viewModel,
			changesViewModel: changesViewModel,
			changesDiffViewModel: changesDiffViewModel,
			commitViewModel: commitViewModel,
			conflictViewModel: conflictViewModel,
			historyViewModel: historyViewModel,
			operationViewModel: operationViewModel,
			referencesViewModel: referencesViewModel,
			syncViewModel: syncViewModel,
			remotesViewModel: remotesViewModel,
			stashesViewModel: stashesViewModel,
			treeViewModel: treeViewModel,
			diffPreferences: diffPreferences,
			changesDiffSearchViewModel: changesDiffSearchViewModel,
			historyDiffSearchViewModel: historyDiffSearchViewModel,
			stashesDiffSearchViewModel: stashesDiffSearchViewModel,
			commitActions: commitActions,
			focusedActionsViewModel: focusedActionsViewModel
		)
	}
}
