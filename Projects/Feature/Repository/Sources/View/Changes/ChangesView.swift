import DomainGitInterface
import SwiftUI

struct ChangesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var pendingDiscardChanges: [WorkingTreeChange]?
	@State private var filterText = ""

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
				isStaged: viewModel.selectedChange?.isStaged == true,
				selectedCount: viewModel.selectedChangeIDs.count,
				diff: viewModel.diff,
				isLoading: viewModel.isLoadingDiff
			)
			.frame(maxWidth: .infinity)
		}
		.navigationTitle(viewModel.repositoryName)
		.navigationSubtitle(viewModel.currentBranchName)
		.safeAreaInset(edge: .bottom) {
			CommitBar(viewModel: viewModel)
		}
		.confirmationDialog(
			discardConfirmationTitle,
			isPresented: discardConfirmationBinding,
			presenting: pendingDiscardChanges
		) { changes in
			Button("Discard Changes", role: .destructive) {
				pendingDiscardChanges = nil
				viewModel.didRequestDiscard(changes)
			}
			Button("Cancel", role: .cancel) {
				pendingDiscardChanges = nil
			}
		} message: { _ in
			Text("This action cannot be undone.")
		}
	}

	private var discardConfirmationTitle: String {
		guard let pendingDiscardChanges else { return "Discard Changes?" }
		guard pendingDiscardChanges.count == 1, let change = pendingDiscardChanges.first else {
			return "Discard Changes to \(pendingDiscardChanges.count) Files?"
		}
		let fileName = URL(fileURLWithPath: change.path).lastPathComponent
		return "Discard Changes to “\(fileName)”?"
	}

	private var discardConfirmationBinding: Binding<Bool> {
		Binding(
			get: { pendingDiscardChanges != nil },
			set: { isPresented in
				if !isPresented {
					pendingDiscardChanges = nil
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
				List(selection: $viewModel.selectedChangeIDs) {
					if viewModel.isAmendingCommit, !viewModel.amendChanges.isEmpty {
						Section {
							ForEach(filteredAmendChanges) { change in
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
								count: filteredAmendChanges.count
							)
						}
					}

					if !filteredStagedChanges.isEmpty {
						Section {
							workingTreeRows(filteredStagedChanges)
						} header: {
							ChangeListSectionHeader(
								title: "Staged",
								count: filteredStagedChanges.count
							)
						}
					}

					if !filteredUnstagedChanges.isEmpty {
						Section {
							workingTreeRows(filteredUnstagedChanges)
						} header: {
							ChangeListSectionHeader(
								title: "Unstaged",
								count: filteredUnstagedChanges.count
							)
						}
					}
				}
				.listStyle(.plain)
				.safeAreaInset(edge: .bottom) {
					TextField("Filter Files", text: $filterText)
						.textFieldStyle(.roundedBorder)
						.padding(10)
						.background(.bar)
				}
			}
		}
		.onChange(of: viewModel.selectedChangeIDs) {
			viewModel.didChangeSelectedChanges()
		}
	}

	private func workingTreeRows(_ changes: [WorkingTreeChange]) -> some View {
		ForEach(changes) { change in
			ChangeRow(
				change: change,
				isStaged: change.isStaged,
				onSetStaged: { isStaged in
					if isStaged {
						viewModel.didRequestStage([change])
					} else {
						viewModel.didRequestUnstage([change])
					}
				}
			)
			.tag(WorkspaceChangeSelection.workingTree(change.id))
			.listRowSeparator(.hidden)
			.contextMenu {
				changeContextMenu(for: change)
			}
		}
	}

	private var stageAllChanges: [WorkingTreeChange] {
		viewModel.displayedWorkingTreeChanges.filter(\.hasWorkingTreeChange)
	}

	private var filteredStagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter(\.isStaged)
	}

	private var filteredUnstagedChanges: [WorkingTreeChange] {
		filteredWorkingTreeChanges.filter { !$0.isStaged }
	}

	private var filteredWorkingTreeChanges: [WorkingTreeChange] {
		viewModel.displayedWorkingTreeChanges.filter(matchesFilter)
	}

	private var filteredAmendChanges: [GitAmendChange] {
		viewModel.amendChanges.filter(matchesFilter)
	}

	private var selectedFileName: String? {
		selectedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent }
	}

	private var selectedFilePath: String? {
		viewModel.selectedChange?.path ?? viewModel.selectedAmendChange?.path
	}

	private var selectedFileState: GitFileState? {
		viewModel.selectedChange?.displayState ?? viewModel.selectedAmendChange?.state
	}

	private var selectedFileActionTitle: String? {
		guard let change = viewModel.selectedChange else { return nil }
		return change.hasWorkingTreeChange ? "Stage" : change.isStaged ? "Unstage" : nil
	}

	private func applySelectedFileAction() {
		guard let change = viewModel.selectedChange else { return }
		if change.hasWorkingTreeChange {
			viewModel.didRequestStage([change])
		} else if change.isStaged {
			viewModel.didRequestUnstage([change])
		}
	}

	private func matchesFilter(_ change: WorkingTreeChange) -> Bool {
		matchesFilter(path: change.path)
	}

	private func matchesFilter(_ change: GitAmendChange) -> Bool {
		matchesFilter(path: change.path)
	}

	private func matchesFilter(path: String) -> Bool {
		let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !query.isEmpty else { return true }
		return path.localizedCaseInsensitiveContains(query)
	}

	@ViewBuilder
	private func changeContextMenu(for change: WorkingTreeChange) -> some View {
		let changes = contextChanges(for: change)
		let stageableChanges = changes.filter(\.hasWorkingTreeChange)
		let stagedChanges = changes.filter(\.isStaged)

		if !stageableChanges.isEmpty {
			Button("Stage Changes", systemImage: "plus.circle") {
				viewModel.didRequestStage(stageableChanges)
			}
			.disabled(viewModel.isLoading)
		}

		if !stagedChanges.isEmpty, !viewModel.isAmendingCommit {
			Button("Unstage Changes", systemImage: "minus.circle") {
				viewModel.didRequestUnstage(stagedChanges)
			}
			.disabled(viewModel.isLoading)
		}

		Divider()

		Button(
			"Discard Changes…",
			systemImage: "trash",
			role: .destructive
		) {
			pendingDiscardChanges = changes
		}
		.disabled(viewModel.isLoading)
	}

	@ViewBuilder
	private func amendContextMenu(for change: GitAmendChange) -> some View {
		let changes = contextAmendChanges(for: change)
		Button("Unstage Changes", systemImage: "minus.circle") {
			viewModel.didRequestUnstageFromAmend(changes)
		}
		.disabled(viewModel.isLoading)
	}

	private func contextChanges(for change: WorkingTreeChange) -> [WorkingTreeChange] {
		guard viewModel.selectedChangeIDs.contains(.workingTree(change.id)) else { return [change] }
		return viewModel.selectedChanges
	}

	private func contextAmendChanges(for change: GitAmendChange) -> [GitAmendChange] {
		guard viewModel.selectedChangeIDs.contains(.amend(change.id)) else { return [change] }
		return viewModel.selectedAmendChanges
	}
}
