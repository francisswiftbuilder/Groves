import DomainGitInterface
import SwiftUI

struct ChangesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		EqualWidthHSplitView(
			proportions: [0.24, 0.53, 0.23],
			minimumWidths: [180, 300, 210]
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
		.confirmationDialog(
			viewModel.discardConfirmationTitle,
			isPresented: discardConfirmationBinding,
			presenting: viewModel.pendingDiscardChanges
		) { _ in
			Button("Discard Changes", role: .destructive) {
				viewModel.didConfirmDiscardChanges()
			}
			Button("Cancel", role: .cancel) {
				viewModel.didDismissDiscardConfirmation()
			}
		} message: { _ in
			Text("This action cannot be undone.")
		}
	}

	private var discardConfirmationBinding: Binding<Bool> {
		Binding(
			get: { viewModel.pendingDiscardChanges != nil },
			set: { isPresented in
				if !isPresented {
					viewModel.didDismissDiscardConfirmation()
				}
			}
		)
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
			DiffView(
				diff: viewModel.diff,
				changedFileCount: viewModel.changes.count,
				fileName: selectedFileName,
				filePath: selectedFilePath,
				fileState: selectedFileState,
				fileActionTitle: selectedFileActionTitle,
				lineAction: viewModel.selectedDiffLineAction,
				isLoadingDiff: viewModel.isLoadingDiff,
				isApplyingAction: viewModel.isApplyingDiffLine,
				onApplyFileAction: applySelectedFileAction,
				onApplyLine: viewModel.didRequestApplyDiffLine
			)
		}
	}

	private var changesTitleHeader: some View {
		HStack(alignment: .center) {
			VStack(alignment: .leading, spacing: 2) {
				Text("Changes")
					.font(.title2.weight(.semibold))
				Text(navigationSubtitle)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 8)
		}
		.padding(.horizontal, 16)
		.frame(height: 64)
	}

	private var changesActionsHeader: some View {
		HStack(alignment: .center, spacing: 10) {
			Spacer(minLength: 16)
			Button("Stage All") {
				viewModel.didRequestStage(stageAllChanges)
			}
			.buttonStyle(.bordered)
			.controlSize(.small)
			.disabled(stageAllChanges.isEmpty || viewModel.isLoading)

			Button("Commit") {
				viewModel.didRequestCommit()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
			.disabled(!viewModel.canCommit)
		}
		.padding(.horizontal, 16)
		.frame(height: 64)
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
		viewModel.selectedChange?.path ?? viewModel.selectedAmendChange?.path
	}

	private var selectedFileState: GitFileState? {
		viewModel.selectedFileState
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
