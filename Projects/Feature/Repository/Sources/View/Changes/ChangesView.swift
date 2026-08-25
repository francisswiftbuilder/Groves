import DomainGitInterface
import SwiftUI

struct ChangesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		EqualWidthHSplitView(
			proportions: [0.27, 0.50, 0.23],
			minimumWidths: [200, 300, 210]
		) {
			changesListPane
				.frame(maxWidth: .infinity)
		} center: {
			changesDiffPane
				.frame(maxWidth: .infinity)
		} trailing: {
			ChangeInspectorView(
				fileName: selectedFileName,
				filePath: selectedFilePath,
				fileState: selectedFileState,
				isStaged: viewModel.selectedDiffSource == .staged,
				selectedCount: viewModel.selectedChangeIDs.count,
				diff: viewModel.diff,
				isLoading: viewModel.isLoadingDiff
			)
			.frame(maxWidth: .infinity)
		}
		.navigationTitle(viewModel.repositoryName)
		.navigationSubtitle(viewModel.currentBranchStatus)
		.safeAreaInset(edge: .bottom) {
			CommitBar(viewModel: viewModel)
		}
	}

	private var navigationSubtitle: String {
		guard viewModel.isAmendingCommit else {
			return "\(viewModel.changes.count) working tree items"
		}
		return
			"\(viewModel.displayedWorkingTreeChanges.count) working tree items · \(viewModel.amendChanges.count) in amend"
	}

	private var changesListPane: some View {
		VStack(spacing: 0) {
			changesTitleHeader
			Divider()
			changeList
		}
	}

	private var changesDiffPane: some View {
		VStack(spacing: 0) {
			changesActionsHeader
			Divider()
			if let conflict = viewModel.selectedConflict {
				ConflictPreview(viewModel: viewModel, conflict: conflict)
			} else {
				DiffView(
					options: $viewModel.diffOptions,
					presentationMode: $viewModel.diffPresentationMode,
					diff: viewModel.diff,
					imageDiff: viewModel.imageDiff,
					changedFileCount: viewModel.changes.count,
					fileName: selectedFileName,
					filePath: selectedFilePath,
					fileState: selectedFileState,
					fileActionTitle: selectedFileActionTitle,
					lineAction: viewModel.selectedDiffLineAction,
					hunkActions: viewModel.selectedDiffHunkActions,
					isLoadingDiff: viewModel.isLoadingDiff,
					isApplyingAction: viewModel.isApplyingDiffLine,
					onOptionsChanged: viewModel.didChangeDiffOptions,
					onApplyFileAction: applySelectedFileAction,
					onApplyLine: viewModel.didRequestApplyDiffLine,
					onApplyHunk: viewModel.didRequestApplyDiffHunk
				)
			}
		}
	}

	private var changesTitleHeader: some View {
		HStack(alignment: .center) {
			VStack(alignment: .leading, spacing: 2) {
				Text("Changes")
					.font(.headline)
				Text(navigationSubtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 8)
		}
		.padding(.horizontal, 12)
		.frame(height: 52)
		.background(.bar)
	}

	private var changesActionsHeader: some View {
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

	private var changeList: some View {
		Group {
			if viewModel.displayedWorkingTreeChanges.isEmpty,
				!viewModel.isAmendingCommit || viewModel.amendChanges.isEmpty
			{
				EmptyStateView(
					title: "Working Tree Clean",
					message: "There are no staged or unstaged changes.",
					systemImage: "checkmark.circle"
				)
			} else {
				List(selection: selectedChangesBinding) {
					if !viewModel.filteredConflicts.isEmpty {
						Section {
							ForEach(viewModel.filteredConflicts) { conflict in
								ConflictRow(conflict: conflict) {
									viewModel.didOpenConflictInEditor(conflict)
								}
								.tag(WorkspaceChangeSelection.conflict(conflict.path))
								.listRowSeparator(.hidden)
								.contextMenu {
									conflictActions(conflict)
								}
							}
						} header: {
							ChangeListSectionHeader(
								title: "Conflicts",
								count: viewModel.filteredConflicts.count
							)
						}
					}

					if viewModel.isAmendingCommit, !viewModel.amendChanges.isEmpty {
						Section {
							ForEach(viewModel.filteredAmendChanges) { change in
								AmendChangeRow(change: change) {
									viewModel.didRequestUnstageFromAmend([change])
								}
								.tag(WorkspaceChangeSelection.amend(change.id))
								.listRowSeparator(.hidden)
								.contextMenu {
									amendContextMenu(for: change)
								}
							}
						} header: {
							ChangeListSectionHeader(
								title: "Included in Amended Commit",
								count: viewModel.filteredAmendChanges.count
							)
						}
					}

					if !viewModel.filteredStagedChanges.isEmpty {
						Section {
							workingTreeRows(viewModel.filteredStagedChanges, source: .staged)
						} header: {
							ChangeListSectionHeader(
								title: "Staged",
								count: viewModel.filteredStagedChanges.count
							)
						}
					}

					if !viewModel.filteredUnstagedChanges.isEmpty {
						Section {
							workingTreeRows(viewModel.filteredUnstagedChanges, source: .unstaged)
						} header: {
							ChangeListSectionHeader(
								title: "Unstaged",
								count: viewModel.filteredUnstagedChanges.count
							)
						}
					}
				}
				.listStyle(.plain)
				.safeAreaInset(edge: .bottom) {
					TextField("Filter Files", text: $viewModel.changeFilterText)
						.textFieldStyle(.roundedBorder)
						.padding(10)
						.background(.bar)
				}
			}
		}
	}

	private var selectedChangesBinding: Binding<Set<WorkspaceChangeSelection>> {
		Binding(
			get: { viewModel.selectedChangeIDs },
			set: { selections in
				Task { await viewModel.didSelectChanges(selections) }
			}
		)
	}

	private func workingTreeRows(
		_ changes: [WorkingTreeChange],
		source: GitDiffSource
	) -> some View {
		ForEach(changes) { change in
			ChangeRow(
				change: change,
				state: source == .staged ? change.indexState : change.workingTreeState,
				isStaged: source == .staged,
				onSetStaged: { isStaged in
					if isStaged {
						viewModel.didRequestStage([change])
					} else {
						viewModel.didRequestUnstage([change])
					}
				}
			)
			.tag(changeSelection(change, source: source))
			.listRowSeparator(.hidden)
			.contextMenu {
				changeContextMenu(for: change, source: source)
			}
		}
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
		case .staged:
			return "Unstage"
		case .unstaged:
			return "Stage"
		case .none:
			return nil
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

	@ViewBuilder
	private func changeContextMenu(
		for change: WorkingTreeChange,
		source: GitDiffSource
	) -> some View {
		let changes = contextChanges(for: change, source: source)

		if source == .unstaged {
			Button("Stage Changes", systemImage: "plus.circle") {
				viewModel.didRequestStage(changes)
			}
			.disabled(viewModel.isLoading)
		}

		if source == .staged, !viewModel.isAmendingCommit {
			Button("Unstage Changes", systemImage: "minus.circle") {
				viewModel.didRequestUnstage(changes)
			}
			.disabled(viewModel.isLoading)
		}

		if source == .unstaged {
			Divider()

			Button(
				"Discard Changes…",
				systemImage: "trash",
				role: .destructive
			) {
				viewModel.didPresentDiscardConfirmation(for: changes)
			}
			.disabled(viewModel.isLoading)
		}
	}

	@ViewBuilder
	private func amendContextMenu(for change: GitAmendChange) -> some View {
		let changes = contextAmendChanges(for: change)
		Button("Unstage Changes", systemImage: "minus.circle") {
			viewModel.didRequestUnstageFromAmend(changes)
		}
		.disabled(viewModel.isLoading)
	}

	@ViewBuilder
	private func conflictActions(_ conflict: GitConflict) -> some View {
		Button(viewModel.oursConflictLabel, systemImage: "arrow.down.doc") {
			viewModel.didResolveConflict(conflict, using: .ours)
		}
		Button(viewModel.theirsConflictLabel, systemImage: "arrow.down.doc.fill") {
			viewModel.didResolveConflict(conflict, using: .theirs)
		}
		Divider()
		Button("Mark Resolved", systemImage: "checkmark.circle") {
			viewModel.didMarkConflictResolved(conflict)
		}
		Button("Open in Editor", systemImage: "square.and.pencil") {
			viewModel.didOpenConflictInEditor(conflict)
		}
		.disabled(!conflictFileExists(conflict))
	}

	private func conflictFileExists(_ conflict: GitConflict) -> Bool {
		guard let repositoryURL = viewModel.repositoryURL else { return false }
		return FileManager.default.fileExists(atPath: repositoryURL.appending(path: conflict.path).path)
	}

	private func contextChanges(
		for change: WorkingTreeChange,
		source: GitDiffSource
	) -> [WorkingTreeChange] {
		let selection = changeSelection(change, source: source)
		guard viewModel.selectedChangeIDs.contains(selection) else { return [change] }
		return source == .staged
			? viewModel.selectedStagedChanges
			: viewModel.selectedUnstagedChanges
	}

	private func changeSelection(
		_ change: WorkingTreeChange,
		source: GitDiffSource
	) -> WorkspaceChangeSelection {
		source == .staged ? .staged(change.id) : .unstaged(change.id)
	}

	private func contextAmendChanges(for change: GitAmendChange) -> [GitAmendChange] {
		guard viewModel.selectedChangeIDs.contains(.amend(change.id)) else { return [change] }
		return viewModel.selectedAmendChanges
	}
}
