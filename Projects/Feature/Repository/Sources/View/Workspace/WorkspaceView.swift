import CoreRepositoryDiff
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryInterface
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import FeatureRepositoryTree
import SwiftUI

struct WorkspaceView: View {
	@Environment(\.scenePhase) private var scenePhase
	@ObservedObject var viewModel: WorkspaceViewModel
	@ObservedObject var windowViewModel: RepositoryWindowViewModel
	@ObservedObject private var historyViewModel: HistoryViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var referencesViewModel: RepositoryReferencesViewModel
	@ObservedObject private var syncViewModel: RepositorySyncViewModel
	@ObservedObject private var remotesViewModel: RemotesViewModel
	let changesViewModel: ChangesViewModel
	let changesDiffViewModel: ChangesDiffViewModel
	let commitViewModel: CommitViewModel
	let conflictViewModel: ConflictViewModel
	let stashesViewModel: StashesViewModel
	let treeViewModel: RepositoryTreeViewModel
	let diffPreferences: WorkspaceDiffPreferences
	let commitActions: RepositoryCommitActions
	let focusedActions: () -> RepositoryFocusedActions
	let repositoryID: RepositoryTab.ID

	init(
		viewModel: WorkspaceViewModel,
		windowViewModel: RepositoryWindowViewModel,
		changesViewModel: ChangesViewModel,
		changesDiffViewModel: ChangesDiffViewModel,
		commitViewModel: CommitViewModel,
		conflictViewModel: ConflictViewModel,
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		referencesViewModel: RepositoryReferencesViewModel,
		syncViewModel: RepositorySyncViewModel,
		remotesViewModel: RemotesViewModel,
		stashesViewModel: StashesViewModel,
		treeViewModel: RepositoryTreeViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		commitActions: RepositoryCommitActions,
		focusedActions: @escaping () -> RepositoryFocusedActions,
		repositoryID: RepositoryTab.ID
	) {
		self.viewModel = viewModel
		self.windowViewModel = windowViewModel
		self.changesViewModel = changesViewModel
		self.changesDiffViewModel = changesDiffViewModel
		self.commitViewModel = commitViewModel
		self.conflictViewModel = conflictViewModel
		_historyViewModel = ObservedObject(wrappedValue: historyViewModel)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_referencesViewModel = ObservedObject(wrappedValue: referencesViewModel)
		_syncViewModel = ObservedObject(wrappedValue: syncViewModel)
		_remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
		self.stashesViewModel = stashesViewModel
		self.treeViewModel = treeViewModel
		self.diffPreferences = diffPreferences
		self.commitActions = commitActions
		self.focusedActions = focusedActions
		self.repositoryID = repositoryID
	}

	var body: some View {
		RepositoryReferencesPresentationHost(
			viewModel: referencesViewModel,
			onConfirmDeleteTag: clearDeletedSidebarSelection
		) {
			RepositorySyncPresentationHost(viewModel: syncViewModel) {
				RepositoryRemotePresentationHost(viewModel: remotesViewModel) {
					RepositoryOperationPresentationHost(viewModel: operationViewModel) {
						NavigationSplitView {
							RepositorySidebar(
								viewModel: viewModel,
								windowViewModel: windowViewModel,
								changesViewModel: changesViewModel,
								operationViewModel: operationViewModel,
								referencesViewModel: referencesViewModel,
								remotesViewModel: remotesViewModel,
								stashesViewModel: stashesViewModel,
								repositoryID: repositoryID
							)
							.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
						} detail: {
							WorkspaceDetail(
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
								commitActions: commitActions
							)
						}
					}
				}
			}
		}
		.task(id: workingTreeMonitorID) {
			guard scenePhase == .active else { return }
			await viewModel.monitorRepositoryChanges()
		}
		.focusedSceneValue(\.repositoryActions, focusedActions())
	}

	private func clearDeletedSidebarSelection(for tag: GitTag) {
		guard case .tag(let repositoryID, let id) = windowViewModel.sidebarSelection else { return }
		guard tag.id == id, repositoryID == self.repositoryID else { return }
		windowViewModel.selectSidebarItem(nil)
	}

	private var workingTreeMonitorID: WorkingTreeMonitorID {
		WorkingTreeMonitorID(
			repositoryURL: viewModel.repositoryURL,
			scenePhase: scenePhase
		)
	}

}
