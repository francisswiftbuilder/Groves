import CoreRepositoryDiff
import DomainGitInterface
import Foundation
import SwiftUI

struct ChangesDiffPane: View {
	private let searchViewModel: RepositorySearchViewModel
	@ObservedObject private var viewModel: ChangesViewModel
	@ObservedObject private var diffViewModel: ChangesDiffViewModel
	@ObservedObject private var conflictViewModel: ConflictViewModel
	@ObservedObject private var preferences: WorkspaceDiffPreferences
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
		_viewModel = ObservedObject(wrappedValue: viewModel)
		_diffViewModel = ObservedObject(wrappedValue: diffViewModel)
		_conflictViewModel = ObservedObject(wrappedValue: conflictViewModel)
		_preferences = ObservedObject(wrappedValue: preferences)
		self.repositoryURL = repositoryURL
		self.onOptionsChanged = onOptionsChanged
	}

	var body: some View {
		VStack(spacing: 0) {
			actionsHeader
			Divider()
			if let conflict = viewModel.selectedConflict {
				ConflictPreview(
					viewModel: conflictViewModel,
					repositoryURL: repositoryURL,
					conflict: conflict
				)
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
					fileActionTitle: selectedFileActionTitle,
					lineAction: diffViewModel.selectedDiffLineAction,
					hunkActions: diffViewModel.selectedDiffHunkActions,
					isLoadingDiff: diffViewModel.isLoading,
					isApplyingAction: diffViewModel.isApplyingAction,
					onOptionsChanged: onOptionsChanged,
					onApplyFileAction: applySelectedFileAction,
					onApplyLine: diffViewModel.didRequestApplyDiffLine,
					onApplyHunk: diffViewModel.didRequestApplyDiffHunk
				)
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

	private var actionsHeader: some View {
		HStack(alignment: .center, spacing: 10) {
			Text("Working Tree")
				.font(.subheadline.weight(.semibold))
			Spacer(minLength: 12)
			Button("Stage All", systemImage: "plus.circle") {
				viewModel.didRequestStage(stageAllChanges)
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
			.disabled(stageAllChanges.isEmpty || viewModel.isLoading)
		}
		.padding(.horizontal, 12)
		.frame(height: 52)
		.background(.bar)
	}

	private var stageAllChanges: [WorkingTreeChange] {
		viewModel.displayedWorkingTreeChanges.filter(\.hasWorkingTreeChange)
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

	private var selectedFileActionTitle: String? {
		guard viewModel.selectedChange != nil else { return nil }
		switch viewModel.selectedDiffSource {
		case .staged: return "Unstage"
		case .unstaged: return "Stage"
		case .none: return nil
		}
	}

	private func applySelectedFileAction() {
		guard let change = viewModel.selectedChange else { return }
		if viewModel.selectedDiffSource == .unstaged {
			viewModel.didRequestStage([change])
		} else if viewModel.selectedDiffSource == .staged {
			viewModel.didRequestUnstage([change])
		}
	}
}
