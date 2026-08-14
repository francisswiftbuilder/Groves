import DomainGitInterface
import SwiftUI

struct ChangesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var pendingDiscardChanges: [WorkingTreeChange]?

	var body: some View {
		GeometryReader { geometry in
			HSplitView {
				changeList
					.frame(width: changeListWidth(for: geometry.size.width))
				DiffView(
					diff: viewModel.diff,
					lineAction: viewModel.selectedDiffLineAction,
					isLoading: viewModel.isApplyingDiffLine,
					onApplyLine: viewModel.didRequestApplyDiffLine
				)
				.frame(minWidth: 320, maxWidth: .infinity)
			}
		}
		.navigationTitle("Changes")
		.navigationSubtitle(navigationSubtitle)
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

	private func changeListWidth(for availableWidth: CGFloat) -> CGFloat {
		min(max(availableWidth * 0.4, 220), 360)
	}

	private var navigationSubtitle: String {
		guard viewModel.isAmendingCommit else {
			return "\(viewModel.changes.count) working tree items"
		}
		return
			"\(viewModel.displayedWorkingTreeChanges.count) working tree items · \(viewModel.amendChanges.count) in amend"
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
						Section("Included in Amended Commit") {
							ForEach(viewModel.amendChanges) { change in
								AmendChangeRow(change: change)
									.tag(WorkspaceChangeSelection.amend(change.id))
									.listRowSeparator(.hidden)
									.contextMenu {
										amendContextMenu(for: change)
									}
							}
						}
					}

					if viewModel.isAmendingCommit, !viewModel.displayedWorkingTreeChanges.isEmpty {
						Section("Working Tree") {
							workingTreeRows
						}
					} else {
						workingTreeRows
					}
				}
				.listStyle(.inset)
			}
		}
		.onChange(of: viewModel.selectedChangeIDs) {
			viewModel.didChangeSelectedChanges()
		}
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					viewModel.didRequestStage(viewModel.selectedStageableChanges)
				} label: {
					Label("Stage", systemImage: "plus")
				}
				.disabled(
					viewModel.selectedStageableChanges.isEmpty || viewModel.isLoading
				)

				Button {
					if viewModel.isAmendingCommit {
						viewModel.didRequestUnstageFromAmend(viewModel.selectedAmendChanges)
					} else {
						viewModel.didRequestUnstage(viewModel.selectedChanges)
					}
				} label: {
					Label("Unstage", systemImage: "minus")
				}
				.disabled(
					(viewModel.isAmendingCommit
						? viewModel.selectedAmendChanges.isEmpty
						: !viewModel.selectedChanges.contains(where: \.isStaged))
						|| viewModel.isLoading
				)
			}
		}
	}

	private var workingTreeRows: some View {
		ForEach(viewModel.displayedWorkingTreeChanges) { change in
			ChangeRow(
				change: change,
				showsStagedState: !viewModel.isAmendingCommit
			)
			.tag(WorkspaceChangeSelection.workingTree(change.id))
			.listRowSeparator(.hidden)
			.contextMenu {
				changeContextMenu(for: change)
			}
		}
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

private struct ChangeRow: View {
	let change: WorkingTreeChange
	let showsStagedState: Bool

	var body: some View {
		HStack(spacing: 10) {
			GitStatusBadge(state: change.displayState)
			VStack(alignment: .leading, spacing: 2) {
				Text(URL(fileURLWithPath: change.path).lastPathComponent)
					.lineLimit(1)
				Text(change.path)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 8)
			if showsStagedState, change.isStaged {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
					.accessibilityLabel("Staged")
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}

private struct AmendChangeRow: View {
	let change: GitAmendChange

	var body: some View {
		HStack(spacing: 10) {
			GitStatusBadge(state: change.state)
			VStack(alignment: .leading, spacing: 2) {
				Text(URL(fileURLWithPath: change.path).lastPathComponent)
					.lineLimit(1)
				Text(change.path)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 8)
			Image(systemName: "checkmark.seal.fill")
				.foregroundStyle(.secondary)
				.accessibilityLabel("Included in Amended Commit")
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
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
