import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import Foundation
import SwiftUI

struct ChangesDiffPane: View {
	private let searchViewModel: RepositorySearchViewModel
	private let viewModel: ChangesViewModel
	private let diffViewModel: ChangesDiffViewModel
	private let conflictViewModel: ConflictViewModel
	@Bindable private var preferences: WorkspaceDiffPreferences
	let repositoryURL: URL?
	let onOptionsChanged: () -> Void

	init(
		searchViewModel: RepositorySearchViewModel,
		viewModel: ChangesViewModel,
		diffViewModel: ChangesDiffViewModel,
		conflictViewModel: ConflictViewModel,
		preferences: WorkspaceDiffPreferences,
		repositoryURL: URL?,
		onOptionsChanged: @escaping () -> Void
	) {
		self.searchViewModel = searchViewModel
		self.viewModel = viewModel
		self.diffViewModel = diffViewModel
		self.conflictViewModel = conflictViewModel
		_preferences = Bindable(wrappedValue: preferences)
		self.repositoryURL = repositoryURL
		self.onOptionsChanged = onOptionsChanged
	}

	var body: some View {
		VStack(spacing: 0) {
			if let conflict = viewModel.selectedConflict {
				ConflictPreview(
					viewModel: conflictViewModel,
					repositoryURL: repositoryURL,
					conflict: conflict
				)
			} else if viewModel.selectedChangeIDs.count > 1 {
				EmptyStateView(
					title: "\(viewModel.selectedChangeIDs.count) Changes Selected",
					systemImage: "doc.on.doc")
			} else {
				DiffView(
					searchModel: searchViewModel,
					options: $preferences.options,
					presentationMode: $preferences.presentationMode,
					sourceID: viewModel.selectedDiffSourceID,
					diff: diffViewModel.diff,
					imageDiff: diffViewModel.imageDiff,
					changedFileCount: viewModel.changes.count,
					fileName: selectedFileName,
					filePath: selectedFilePath,
					fileState: selectedFileState,
					fileActionTitle: nil,
					lineAction: diffViewModel.selectedDiffLineAction,
					hunkActions: diffViewModel.selectedDiffHunkActions,
					isLoadingDiff: diffViewModel.isLoading,
					isApplyingAction: diffViewModel.isApplyingAction,
					onOptionsChanged: onOptionsChanged,
					onApplyFileAction: {},
					onApplyLine: diffViewModel.didRequestApplyDiffLine,
					onApplyHunk: diffViewModel.didRequestApplyDiffHunk
				)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .top, spacing: 0) {
			VStack(spacing: 0) {
				ChangesActionBar(viewModel: viewModel)
				Divider()
			}
		}
		.confirmationDialog(
			diffViewModel.pendingConfirmation?.title ?? "Confirm Changes",
			isPresented: pendingConfirmationPresentation
		) {
			if let confirmation = diffViewModel.pendingConfirmation {
				Button(confirmation.actionTitle, role: .destructive) {
					diffViewModel.didConfirmPendingConfirmation()
				}
			}
			Button("Cancel", role: .cancel) {
				diffViewModel.didDismissPendingConfirmation()
			}
		} message: {
			Text(diffViewModel.pendingConfirmation?.message ?? "")
		}
	}

	private var pendingConfirmationPresentation: Binding<Bool> {
		Binding(
			get: { diffViewModel.pendingConfirmation != nil },
			set: { isPresented in
				if !isPresented {
					diffViewModel.didDismissPendingConfirmation()
				}
			}
		)
	}

	private var selectedFileName: String? {
		selectedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent }
	}

	private var selectedFilePath: String? {
		viewModel.selectedConflict?.path
			?? viewModel.selectedChange?.path
			?? viewModel.selectedAmendChange?.path
	}

	private var selectedFileState: GitFileState? {
		viewModel.selectedConflict == nil ? viewModel.selectedFileState : .unmerged
	}

}
