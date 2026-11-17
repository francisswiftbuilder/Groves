import CoreRepositoryDiff
import SwiftUI

struct HistoryCommitDiffView: View {
	let historyViewModel: HistoryViewModel
	let searchViewModel: RepositorySearchViewModel
	@Bindable var preferences: WorkspaceDiffPreferences
	let onOptionsChanged: () -> Void

	var body: some View {
		CommitDiffView(
			searchModel: searchViewModel,
			options: $preferences.options,
			presentationMode: $preferences.presentationMode,
			file: historyViewModel.selectedCommitFile,
			imageDiff: historyViewModel.commitImageDiff,
			beforeImageTitle: "Parent",
			afterImageTitle: "Commit",
			changedFileCount: historyViewModel.selectedCommitFiles.count,
			isLoading: historyViewModel.isLoadingCommitDiff || historyViewModel.isLoadingCommitImageDiff,
			onOptionsChanged: onOptionsChanged
		)
	}
}
