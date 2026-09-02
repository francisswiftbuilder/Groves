import CoreRepositoryDiff
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryHistory
import FeatureRepositoryOperations
import FeatureRepositoryStashes
import FeatureRepositoryTree
import SwiftUI

struct WorkspaceView: View {
	let workspace: RepositoryWorkspace
	let windowViewModel: RepositoryWindowViewModel
	let repositoryID: RepositoryTab.ID

	var body: some View {
		RepositoryReferencesPresentationHost(
			viewModel: workspace.referencesViewModel,
			onConfirmDeleteTag: clearDeletedSidebarSelection
		) {
			RepositorySyncPresentationHost(viewModel: workspace.syncViewModel) {
				RepositoryRemotePresentationHost(viewModel: workspace.remotesViewModel) {
					RepositoryOperationPresentationHost(viewModel: workspace.operationViewModel) {
						NavigationSplitView {
							RepositorySidebar(
								viewModel: workspace.viewModel,
								windowViewModel: windowViewModel,
								changesViewModel: workspace.changesViewModel,
								operationViewModel: workspace.operationViewModel,
								referencesViewModel: workspace.referencesViewModel,
								remotesViewModel: workspace.remotesViewModel,
								stashesViewModel: workspace.stashesViewModel,
								repositoryID: repositoryID
							)
							.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
						} detail: {
							WorkspaceDetail(
								viewModel: workspace.viewModel,
								changesViewModel: workspace.changesViewModel,
								changesDiffViewModel: workspace.changesDiffViewModel,
								commitViewModel: workspace.commitViewModel,
								conflictViewModel: workspace.conflictViewModel,
								historyViewModel: workspace.historyViewModel,
								operationViewModel: workspace.operationViewModel,
								referencesViewModel: workspace.referencesViewModel,
								syncViewModel: workspace.syncViewModel,
								remotesViewModel: workspace.remotesViewModel,
								stashesViewModel: workspace.stashesViewModel,
								treeViewModel: workspace.treeViewModel,
								diffPreferences: workspace.diffPreferences,
								changesDiffSearchViewModel: workspace.changesDiffSearchViewModel,
								historyDiffSearchViewModel: workspace.historyDiffSearchViewModel,
								stashesDiffSearchViewModel: workspace.stashesDiffSearchViewModel,
								commitActions: workspace.commitActions
							)
						}
					}
				}
			}
		}
		.modifier(RepositoryMonitoringModifier(viewModel: workspace.viewModel))
		.onAppear {
			workspace.onAppear()
		}
		.onDisappear {
			workspace.onDisappear()
		}
		.modifier(
			RepositoryFocusedActionsModifier(
				viewModel: workspace.focusedActionsViewModel
			)
		)
	}

	private func clearDeletedSidebarSelection(for tag: GitTag) {
		guard case .tag(let repositoryID, let id) = windowViewModel.sidebarSelection else { return }
		guard tag.id == id, repositoryID == self.repositoryID else { return }
		windowViewModel.selectSidebarItem(nil)
	}

}
