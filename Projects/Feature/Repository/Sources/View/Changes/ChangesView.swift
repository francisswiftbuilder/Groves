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
		.navigationSubtitle("\(viewModel.changes.count) working tree items")
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

	private var changeList: some View {
		Group {
			if viewModel.changes.isEmpty {
				EmptyStateView(
					title: "Working Tree Clean",
					message: "There are no staged or unstaged changes.",
					systemImage: "checkmark.circle"
				)
			} else {
				List(selection: $viewModel.selectedChangeIDs) {
					ForEach(viewModel.changes) { change in
						ChangeRow(change: change)
							.tag(change.id)
							.listRowSeparator(.hidden)
							.contextMenu {
								changeContextMenu(for: change)
							}
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
					viewModel.didRequestStage(viewModel.selectedChanges)
				} label: {
					Label("Stage", systemImage: "plus")
				}
				.disabled(
					!viewModel.selectedChanges.contains(where: \.hasWorkingTreeChange)
						|| viewModel.isLoading
				)

				Button {
					viewModel.didRequestUnstage(viewModel.selectedChanges)
				} label: {
					Label("Unstage", systemImage: "minus")
				}
				.disabled(
					!viewModel.selectedChanges.contains(where: \.isStaged) || viewModel.isLoading
				)
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

		if !stagedChanges.isEmpty {
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

	private func contextChanges(for change: WorkingTreeChange) -> [WorkingTreeChange] {
		guard viewModel.selectedChangeIDs.contains(change.id) else { return [change] }
		return viewModel.selectedChanges
	}
}

private struct ChangeRow: View {
	let change: WorkingTreeChange

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
			if change.isStaged {
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(.green)
					.accessibilityLabel("Staged")
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}
}

private struct CommitBar: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "text.bubble")
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)
			TextField("Commit message", text: $viewModel.commitMessage)
				.textFieldStyle(.roundedBorder)
				.onSubmit {
					viewModel.didRequestCommit()
				}
			Button("Commit") {
				viewModel.didRequestCommit()
			}
			.buttonStyle(.borderedProminent)
			.keyboardShortcut(.return, modifiers: [.command])
			.disabled(!viewModel.canCommit)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.bar)
	}
}
