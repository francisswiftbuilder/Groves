import FeatureRepositoryInterface
import SwiftUI

struct WorkspaceView: View {
	@Environment(\.scenePhase) private var scenePhase
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	let repositoryID: RepositoryTab.ID

	var body: some View {
		NavigationSplitView {
			RepositorySidebar(
				viewModel: viewModel,
				windowViewModel: windowViewModel,
				repositoryID: repositoryID
			)
			.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		} detail: {
			WorkspaceDetail(viewModel: viewModel)
		}
		.sheet(isPresented: newBranchPresentation) {
			NewBranchSheet(
				name: $viewModel.newBranchName,
				onCancel: viewModel.didDismissNewBranch,
				onCreate: viewModel.didRequestCreateBranch
			)
		}
		.sheet(isPresented: newTagPresentation) {
			if let commit = viewModel.pendingTagCommit {
				NewTagSheet(
					commit: commit,
					name: $viewModel.newTagName,
					message: $viewModel.newTagMessage,
					onCancel: viewModel.didDismissNewTag,
					onCreate: viewModel.didRequestCreateTag
				)
			}
		}
		.sheet(item: $viewModel.pendingBranchRename) { branch in
			BranchRenameSheet(name: $viewModel.branchRenameName) {
				viewModel.didConfirmBranchRename()
			}
		}
		.sheet(item: $viewModel.pendingMainlineAction) { action in
			MainlineSelectionSheet(action: action) { parent in
				viewModel.didPerformPendingMainlineAction(parent: parent)
			}
		}
		.sheet(item: $viewModel.pendingResetCommit) { commit in
			ResetCommitSheet(commit: commit, mode: $viewModel.resetMode) {
				viewModel.didConfirmReset()
			}
		}
		.sheet(item: $viewModel.remoteEditorPresentation) { presentation in
			RemoteEditorSheet(presentation: presentation) { name, fetchURL, pushURL in
				switch presentation {
				case .add:
					viewModel.didRequestAddRemote(
						name: name,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				case .edit(let remote):
					viewModel.didRequestUpdateRemote(
						remote,
						fetchURL: fetchURL,
						pushURL: pushURL
					)
				}
				viewModel.remoteEditorPresentation = nil
			}
		}
		.sheet(item: $viewModel.pendingRemoteRename) { remote in
			RemoteRenameSheet(remote: remote) { newName in
				viewModel.didRequestRenameRemote(remote, to: newName)
				viewModel.pendingRemoteRename = nil
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
		.task(id: workingTreeMonitorID) {
			guard scenePhase == .active else { return }
			await viewModel.monitorRepositoryChanges()
		}
		.focusedSceneValue(\.repositoryActions, focusedActions)
	}

	private var newBranchPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.isPresentingNewBranch },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewBranch()
				}
			}
		)
	}

	private var newTagPresentation: Binding<Bool> {
		Binding(
			get: { viewModel.pendingTagCommit != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissNewTag()
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
		let operation = viewModel.operationState.operation
		let viewConflicts: (() -> Void)? =
			viewModel.operationState.hasConflicts
			? { viewModel.didViewConflicts() }
			: nil
		let continueOperation: (() -> Void)? =
			operation != nil && !viewModel.operationState.hasConflicts
			? { viewModel.didPerformOperationAction(.continue) }
			: nil
		let skipOperation: (() -> Void)? =
			operation != nil && operation?.kind != .merge
			? { viewModel.didPresentOperationAction(.skip) }
			: nil
		let abortOperation: (() -> Void)? =
			operation != nil
			? { viewModel.didPresentOperationAction(.abort) }
			: nil
		let rebaseSelectedBranch: (() -> Void)?
		let renameSelectedBranch: (() -> Void)?
		if let branch = viewModel.selectedBranch {
			rebaseSelectedBranch = { viewModel.didRequestRebase(onto: branch) }
			renameSelectedBranch = { viewModel.didPresentBranchRename(branch) }
		} else {
			rebaseSelectedBranch = nil
			renameSelectedBranch = nil
		}
		let cherryPickSelectedCommit: (() -> Void)?
		let revertSelectedCommit: (() -> Void)?
		let resetSelectedCommit: (() -> Void)?
		if let commit = viewModel.selectedCommit {
			cherryPickSelectedCommit = { viewModel.didPresentCommitAction(.cherryPick(commit)) }
			revertSelectedCommit = { viewModel.didPresentCommitAction(.revert(commit)) }
			resetSelectedCommit = { viewModel.didPresentReset(commit) }
		} else {
			cherryPickSelectedCommit = nil
			revertSelectedCommit = nil
			resetSelectedCommit = nil
		}
		let selectedRemote = viewModel.selectedRemote
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
			addRemote: { viewModel.didPresentAddRemote() },
			renameSelectedRemote: selectedRemote.map { remote in
				{ viewModel.didPresentRemoteRename(remote) }
			},
			editSelectedRemote: selectedRemote.map { remote in
				{ viewModel.didPresentRemoteEditor(remote) }
			},
			deleteSelectedRemote: selectedRemote.map { remote in
				{ viewModel.didPresentRemoteDeletion(remote) }
			}
		)
	}
}
