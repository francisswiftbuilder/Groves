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
				diff: viewModel.diff
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
				isLoading: viewModel.isApplyingDiffLine,
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

private struct ChangeListSectionHeader: View {
	let title: String
	let count: Int

	var body: some View {
		HStack {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
			Spacer(minLength: 8)
			Text(count, format: .number)
				.font(.caption.monospacedDigit())
				.foregroundStyle(.tertiary)
		}
		.textCase(nil)
	}
}

private struct ChangeRow: View {
	let change: WorkingTreeChange
	let isStaged: Bool
	let onSetStaged: (Bool) -> Void

	var body: some View {
		HStack(spacing: 8) {
			Toggle(
				"",
				isOn: Binding(
					get: { isStaged },
					set: { isStaged in
						onSetStaged(isStaged)
					}
				)
			)
			.labelsHidden()
			.toggleStyle(.checkbox)
			.controlSize(.small)

			ChangeFileIcon(path: change.path)

			Text(URL(fileURLWithPath: change.path).lastPathComponent)
				.lineLimit(1)

			Spacer(minLength: 8)

			Text(change.displayState.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(change.displayState.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}

private struct AmendChangeRow: View {
	let change: GitAmendChange
	let onUnstage: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Toggle(
				"",
				isOn: Binding(
					get: { true },
					set: { isIncluded in
						if !isIncluded {
							onUnstage()
						}
					}
				)
			)
			.labelsHidden()
			.toggleStyle(.checkbox)
			.controlSize(.small)

			ChangeFileIcon(path: change.path)

			Text(URL(fileURLWithPath: change.path).lastPathComponent)
				.lineLimit(1)

			Spacer(minLength: 8)

			Text(change.state.listSymbol)
				.font(.caption.weight(.semibold).monospaced())
				.foregroundStyle(change.state.listColor)
				.frame(width: 16, alignment: .trailing)
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}

private struct ChangeFileIcon: View {
	let path: String

	var body: some View {
		Image(systemName: symbolName)
			.symbolRenderingMode(.hierarchical)
			.foregroundStyle(.secondary)
			.frame(width: 18, height: 18)
			.accessibilityHidden(true)
	}

	private var symbolName: String {
		switch URL(fileURLWithPath: path).pathExtension.lowercased() {
		case "swift":
			return "swift"
		case "xcassets":
			return "folder"
		case "md", "txt", "json", "plist", "yml", "yaml":
			return "doc.text"
		case "png", "jpg", "jpeg", "gif", "webp":
			return "photo"
		default:
			return "doc"
		}
	}
}

extension GitFileState {
	fileprivate var listSymbol: String {
		switch self {
		case .added, .copied, .untracked:
			return "A"
		case .deleted:
			return "D"
		case .modified:
			return "M"
		case .renamed:
			return "R"
		case .typeChanged:
			return "T"
		case .unmerged:
			return "U"
		case .ignored:
			return "!"
		case .unchanged:
			return ""
		}
	}

	fileprivate var listColor: Color {
		switch self {
		case .added, .copied, .untracked:
			return .green
		case .deleted:
			return .red
		case .modified, .renamed, .typeChanged:
			return .orange
		case .unmerged:
			return .purple
		case .ignored, .unchanged:
			return .secondary
		}
	}
}

private struct CommitBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
				Image(systemName: "text.bubble")
					.foregroundStyle(.secondary)
					.accessibilityHidden(true)
				TextField("Summary", text: $viewModel.commitSubject)
					.textFieldStyle(.roundedBorder)
				Toggle(
					"Amend",
					isOn: Binding(
						get: { viewModel.isAmendingCommit },
						set: { viewModel.didSetAmendingCommit($0) }
					)
				)
				.toggleStyle(.checkbox)
				.controlSize(.small)
				.disabled(!viewModel.canAmendCommit)
				Button(viewModel.isAmendingCommit ? "Amend" : "Commit") {
					viewModel.didRequestCommit()
				}
				.buttonStyle(.borderedProminent)
				.keyboardShortcut(.return, modifiers: [.command])
				.disabled(!viewModel.canCommit)
			}
			TextField(
				"Description (optional)",
				text: $viewModel.commitBody,
				axis: .vertical
			)
			.textFieldStyle(.roundedBorder)
			.lineLimit(2...5)
			.padding(.leading, 28)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
