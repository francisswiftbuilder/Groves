import FeatureRepositoryInterface
import SwiftUI

struct WorkspaceView: View {
	@Environment(\.scenePhase) private var scenePhase
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	@ObservedObject private var historyViewModel: HistoryViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	let changesViewModel: ChangesViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let repositoryID: RepositoryTab.ID

	init(
		viewModel: WorkspaceViewModel,
		windowViewModel: RepositoryWindowViewModel,
		changesViewModel: ChangesViewModel,
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		stashesViewModel: StashesViewModel,
		treeViewModel: RepositoryTreeViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		repositoryID: RepositoryTab.ID
	) {
		self.viewModel = viewModel
		self.windowViewModel = windowViewModel
		self.changesViewModel = changesViewModel
		_historyViewModel = ObservedObject(wrappedValue: historyViewModel)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
		self.repositoryID = repositoryID
	}

	var body: some View {
		NavigationSplitView {
			RepositorySidebar(
				viewModel: viewModel,
				windowViewModel: windowViewModel,
				changesViewModel: changesViewModel,
				operationViewModel: operationViewModel,
				stashesViewModel: stashesViewModel,
				repositoryID: repositoryID
			)
			.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			WorkspaceDetail(
				viewModel: viewModel,
				changesViewModel: changesViewModel,
				historyViewModel: historyViewModel,
				operationViewModel: operationViewModel,
				stashesViewModel: stashesViewModel,
				treeViewModel: treeViewModel,
				diffPreferences: diffPreferences
			)
		}
		.sheet(isPresented: newBranchPresentation) {
			NewBranchSheet(
				name: $operationViewModel.newBranchName,
				onCancel: operationViewModel.didDismissNewBranch,
				onCreate: operationViewModel.didRequestCreateBranch
			)
		}
		.sheet(isPresented: newTagPresentation) {
			if let commit = operationViewModel.pendingTagCommit {
				NewTagSheet(
					commit: commit,
					name: $operationViewModel.newTagName,
					message: $operationViewModel.newTagMessage,
					onCancel: operationViewModel.didDismissNewTag,
					onCreate: operationViewModel.didRequestCreateTag
				)
			}
		}
		.sheet(item: $operationViewModel.pendingBranchRename) { branch in
			BranchRenameSheet(name: $operationViewModel.branchRenameName) {
				operationViewModel.didConfirmBranchRename()
			}
		}
		.sheet(item: $operationViewModel.pendingMainlineAction) { action in
			MainlineSelectionSheet(action: action) { parent in
				operationViewModel.didPerformPendingMainlineAction(parent: parent)
			}
		}
		.sheet(item: $operationViewModel.pendingResetCommit) { commit in
			ResetCommitSheet(commit: commit, mode: $operationViewModel.resetMode) {
				operationViewModel.didConfirmReset()
			}
		}
		.sheet(item: $operationViewModel.remoteEditorPresentation) { presentation in
			RemoteEditorSheet(presentation: presentation) { name, fetchURL, pushURL in
				switch presentation {
				case .add:
					operationViewModel.didRequestAddRemote(
						name: name,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				case .edit(let remote):
					operationViewModel.didRequestUpdateRemote(
						remote,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				}
				operationViewModel.remoteEditorPresentation = nil
			}
		}
		.sheet(item: $operationViewModel.pendingRemoteRename) { remote in
			RemoteRenameSheet(remote: remote) { newName in
				operationViewModel.didRequestRenameRemote(remote, to: newName)
				operationViewModel.pendingRemoteRename = nil
			}
		}
		.confirmationDialog(
			viewModel.pendingRepositoryConfirmation?.title ?? "Confirm Repository Action",
			isPresented: pendingConfirmationPresentation
		) {
			if let confirmation = viewModel.pendingRepositoryConfirmation {
				Button(confirmation.actionTitle, role: .destructive) {
					clearDeletedSidebarSelection(for: confirmation)
					viewModel.didConfirmPendingRepositoryConfirmation()
				}
			}
			Button("Cancel", role: .cancel) {
				viewModel.didDismissPendingRepositoryConfirmation()
			}
		} message: {
			Text(viewModel.pendingRepositoryConfirmation?.message ?? "")
		}
		.confirmationDialog(
			pullDivergenceTitle,
			isPresented: pullDivergencePresentation
		) {
			Button("Rebase onto Upstream") {
				operationViewModel.didResolvePull(using: .rebase)
			}
			Button("Merge Upstream") {
				operationViewModel.didResolvePull(using: .merge)
			}
			Button("Cancel", role: .cancel) {
				operationViewModel.didDismissPullDivergence()
			}
		} message: {
			if let divergence = operationViewModel.pendingPullDivergence {
				Text(
					"\(divergence.upstream) · ↑\(divergence.aheadCount) · ↓\(divergence.behindCount)"
				)
			}
		}
		.task(id: workingTreeMonitorID) {
			guard scenePhase == .active else { return }
			await viewModel.monitorRepositoryChanges()
		}
		.focusedSceneValue(\.repositoryActions, focusedActions)
	}

	private var newBranchPresentation: Binding<Bool> {
		Binding(
			get: { operationViewModel.isPresentingNewBranch },
			set: { isPresented in
				if !isPresented {
					operationViewModel.didDismissNewBranch()
				}
			}
		)
	}

	private var newTagPresentation: Binding<Bool> {
		Binding(
			get: { operationViewModel.pendingTagCommit != nil },
			set: { isPresented in
				if !isPresented {
					operationViewModel.didDismissNewTag()
				}
			}
		)
	}

	private var pendingConfirmationPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingRepositoryConfirmation != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissPendingRepositoryConfirmation()
				}
			}
		)
	}

	private var pullDivergencePresentation: Binding<Bool> {
		Binding(
			get: { operationViewModel.pendingPullDivergence != nil },
			set: { isPresented in
				if !isPresented {
					operationViewModel.didDismissPullDivergence()
				}
			}
		)
	}

	private var pullDivergenceTitle: String {
		guard let divergence = operationViewModel.pendingPullDivergence else {
			return "Branches Have Diverged"
		}
		return "Choose How to Integrate \(divergence.upstream)"
	}

	private func clearDeletedSidebarSelection(for confirmation: PendingRepositoryConfirmation) {
		guard case .tag(let repositoryID, let id) = windowViewModel.sidebarSelection else { return }
		guard case .deleteTag(let tag) = confirmation, tag.id == id, repositoryID == self.repositoryID
		else { return }
		windowViewModel.selectSidebarItem(nil)
	}

	private var workingTreeMonitorID: WorkingTreeMonitorID {
		WorkingTreeMonitorID(
			repositoryURL: viewModel.repositoryURL,
			scenePhase: scenePhase
		)
	}

	private var focusedActions: RepositoryFocusedActions {
		let operation = operationViewModel.operationState.operation
		let viewConflicts: (() -> Void)? =
			operationViewModel.operationState.hasConflicts
			? { operationViewModel.didViewConflicts() }
			: nil
		let continueOperation: (() -> Void)? =
			operation != nil && !operationViewModel.operationState.hasConflicts
			? { operationViewModel.didPerformOperationAction(.continue) }
			: nil
		let skipOperation: (() -> Void)? =
			operation != nil && operation?.kind != .merge
			? { operationViewModel.didPresentOperationAction(.skip) }
			: nil
		let abortOperation: (() -> Void)? =
			operation != nil
			? { operationViewModel.didPresentOperationAction(.abort) }
			: nil
		let rebaseSelectedBranch: (() -> Void)?
		let renameSelectedBranch: (() -> Void)?
		if let branch = operationViewModel.selectedBranch {
			rebaseSelectedBranch = { operationViewModel.didRequestRebase(onto: branch) }
			renameSelectedBranch = { operationViewModel.didPresentBranchRename(branch) }
		} else {
			rebaseSelectedBranch = nil
			renameSelectedBranch = nil
		}
		let cherryPickSelectedCommit: (() -> Void)?
		let revertSelectedCommit: (() -> Void)?
		let resetSelectedCommit: (() -> Void)?
		if let commit = historyViewModel.selectedCommit {
			cherryPickSelectedCommit = {
				operationViewModel.didPresentCommitAction(.cherryPick(commit))
			}
			revertSelectedCommit = {
				operationViewModel.didPresentCommitAction(.revert(commit))
			}
			resetSelectedCommit = { operationViewModel.didPresentReset(commit) }
		} else {
			cherryPickSelectedCommit = nil
			revertSelectedCommit = nil
			resetSelectedCommit = nil
		}
		let selectedRemote = operationViewModel.selectedRemote
		return RepositoryFocusedActions(
			refresh: { viewModel.didRequestRefresh() },
			viewConflicts: viewConflicts,
			continueOperation: continueOperation,
			skipOperation: skipOperation,
			abortOperation: abortOperation,
			rebaseSelectedBranch: rebaseSelectedBranch,
			renameSelectedBranch: renameSelectedBranch,
			cherryPickSelectedCommit: cherryPickSelectedCommit,
			revertSelectedCommit: revertSelectedCommit,
			resetSelectedCommit: resetSelectedCommit,
			addRemote: { operationViewModel.didPresentAddRemote() },
			renameSelectedRemote: selectedRemote.map { remote in
				{ operationViewModel.didPresentRemoteRename(remote) }
			},
			editSelectedRemote: selectedRemote.map { remote in
				{ operationViewModel.didPresentRemoteEditor(remote) }
			},
			deleteSelectedRemote: selectedRemote.map { remote in
				{ operationViewModel.didPresentRemoteDeletion(remote) }
			}
		)
	}
}
