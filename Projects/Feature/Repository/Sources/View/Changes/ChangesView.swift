import DomainGitInterface
import SwiftUI

struct ChangesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		GeometryReader { geometry in
			HSplitView {
				changeList
					.frame(width: changeListWidth(for: geometry.size.width))
				DiffView(diff: viewModel.diff)
					.frame(minWidth: 320, maxWidth: .infinity)
			}
		}
		.navigationTitle("Changes")
		.navigationSubtitle("\(viewModel.changes.count) working tree items")
		.safeAreaInset(edge: .bottom) {
			CommitBar(viewModel: viewModel)
		}
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
				List(selection: $viewModel.selectedChangeID) {
					ForEach(viewModel.changes) { change in
						ChangeRow(change: change)
							.tag(change.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.onChange(of: viewModel.selectedChangeID) { _, selectedChangeID in
			viewModel.didSelectChange(selectedChangeID)
		}
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					viewModel.didRequestStageSelectedChange()
				} label: {
					Label("Stage", systemImage: "plus")
				}
				.disabled(
					viewModel.selectedChange?.hasWorkingTreeChange != true || viewModel.isLoading
				)
				
				Button {
					viewModel.didRequestUnstageSelectedChange()
				} label: {
					Label("Unstage", systemImage: "minus")
				}
				.disabled(viewModel.selectedChange?.isStaged != true || viewModel.isLoading)
			}
		}
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
