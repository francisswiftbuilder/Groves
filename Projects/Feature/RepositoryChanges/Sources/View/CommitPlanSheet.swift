import DomainGitInterface
import SwiftUI

struct CommitPlanSheet: View {
	@Bindable var viewModel: CommitPlanViewModel

	var body: some View {
		CommitReviewContainer {
			content
		} header: {
			header
		} footer: {
			footer
		}
		.frame(
			width: hasTasks || viewModel.isCommitting ? 980 : 460,
			height: hasTasks || viewModel.isCommitting ? 700 : 240
		)
		.interactiveDismissDisabled(viewModel.isCommitting)
		.onChange(of: viewModel.selectedTaskID) { _, _ in viewModel.selectedUnitID = nil }
		.onDisappear { viewModel.onDisappear() }
	}

	private var hasTasks: Bool { !viewModel.tasks.isEmpty }

	@ViewBuilder
	private var content: some View {
		if viewModel.isGenerating {
			CommitPlanProgressView(progress: viewModel.analysisProgress)
		} else if hasTasks {
			HStack(spacing: 0) {
				List(selection: $viewModel.selectedTaskID) {
					ForEach(viewModel.tasks) { task in
						VStack(alignment: .leading, spacing: 4) {
							Text(task.subject.isEmpty ? "Untitled Commit" : task.subject)
								.lineLimit(3)
							Text(task.unitIDs.count == 1 ? "1 change" : "\(task.unitIDs.count) changes")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.padding(.vertical, 4)
						.help(task.subject)
						.accessibilityElement(children: .combine)
						.tag(task.id)
					}
				}
				.listStyle(.sidebar)
				.frame(width: 250)
				.disabled(viewModel.isBusy)
				Divider()
				CommitTaskEditor(viewModel: viewModel)
					.frame(minWidth: 480)
			}
		} else if viewModel.isCommitting {
			ProgressView("Updating repository…")
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else if let message = viewModel.errorMessage {
			ScrollView {
				Text(message)
					.frame(maxWidth: .infinity, alignment: .leading)
					.textSelection(.enabled)
					.padding(.horizontal, 24)
					.padding(.vertical, 12)
			}
		} else {
			Text(
				viewModel.completedCount == 1
					? "1 commit created." : "\(viewModel.completedCount) commits created."
			)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private var header: some View {
		HStack {
			VStack(alignment: .leading, spacing: 4) {
				Text(title).font(.headline)
				if hasTasks {
					Text("Review the messages and changes, then create all commits in order.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			}
			Spacer()
			if hasTasks {
				Text("\(viewModel.tasks.count) remaining")
					.font(.callout)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 24)
		.padding(.vertical, 20)
	}

	private var title: String {
		if viewModel.isGenerating { return "Preparing Commits" }
		if hasTasks { return "Review Commits" }
		if viewModel.errorMessage != nil { return "Couldn’t Prepare Commits" }
		return "Commits Created"
	}

	private var footer: some View {
		VStack(alignment: .leading, spacing: 12) {
			if hasTasks, let message = viewModel.errorMessage {
				Label(message, systemImage: "exclamationmark.triangle")
					.font(.callout)
					.fixedSize(horizontal: false, vertical: true)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
			}
			HStack(spacing: 12) {
				if viewModel.isCommitting {
					ProgressView().controlSize(.small)
					Text("Creating commits…")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
				if hasTasks, viewModel.completedCount > 0 {
					Text("\(viewModel.completedCount) created")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button(closeTitle) { viewModel.onDisappear() }
					.keyboardShortcut(.cancelAction)
					.disabled(viewModel.isCommitting)
				if viewModel.needsRefresh || (!hasTasks && viewModel.errorMessage != nil) {
					Button("Review Again") { viewModel.didRequestPlan() }
						.disabled(viewModel.isBusy)
				}
				if hasTasks {
					if viewModel.tasks.count > 1 {
						Menu("Commit Options", systemImage: "ellipsis.circle") {
							Button("Create Selected Commit") { viewModel.didRequestCommit() }
								.disabled(!viewModel.canCommit)
						}
						.labelStyle(.iconOnly)
						.menuStyle(.borderlessButton)
						.menuIndicator(.hidden)
						.fixedSize()
						.disabled(viewModel.isBusy)
					}
					Button(
						viewModel.tasks.count == 1 ? "Create Commit" : "Create \(viewModel.tasks.count) Commits"
					) {
						viewModel.didRequestCommitAll()
					}
					.buttonStyle(.borderedProminent)
					.keyboardShortcut(.return, modifiers: .command)
					.disabled(!viewModel.canCommitAll)
				}
			}
		}
		.padding(.horizontal, 24)
		.padding(.bottom, 20)
	}

	private var closeTitle: String {
		if viewModel.isGenerating { return "Cancel" }
		return !hasTasks && viewModel.completedCount > 0 ? "Done" : "Close"
	}
}
