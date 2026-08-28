import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

struct ChangesListView: View {
	@ObservedObject private var viewModel: ChangesViewModel
	@ObservedObject private var commitViewModel: CommitViewModel
	@ObservedObject private var conflictViewModel: ConflictViewModel
	let repositoryURL: URL?

	init(
		viewModel: ChangesViewModel,
		commitViewModel: CommitViewModel,
		conflictViewModel: ConflictViewModel,
		repositoryURL: URL?
	) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
		_commitViewModel = ObservedObject(wrappedValue: commitViewModel)
		_conflictViewModel = ObservedObject(wrappedValue: conflictViewModel)
		self.repositoryURL = repositoryURL
	}

	var body: some View {
		VStack(spacing: 0) {
			titleHeader
			Divider()
			changeList
		}
	}

	private var titleHeader: some View {
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

	private var navigationSubtitle: String {
		guard commitViewModel.isAmendingCommit else {
			return "\(viewModel.changes.count) working tree items"
		}
		return
			"\(viewModel.displayedWorkingTreeChanges.count) working tree items · \(viewModel.amendChanges.count) in amend"
	}

	private var changeList: some View {
		Group {
			if viewModel.displayedWorkingTreeChanges.isEmpty,
				!commitViewModel.isAmendingCommit || viewModel.amendChanges.isEmpty
			{
				EmptyStateView(
					title: "Working Tree Clean",
					message: "There are no staged or unstaged changes.",
					systemImage: "checkmark.circle"
				)
			} else {
				List(selection: selectedChangesBinding) {
					conflictSection
					amendSection
					workingTreeSection(
						title: "Staged",
						changes: viewModel.filteredStagedChanges,
						source: .staged
					)
					workingTreeSection(
						title: "Unstaged",
						changes: viewModel.filteredUnstagedChanges,
						source: .unstaged
					)
				}
				.listStyle(.plain)
				.safeAreaInset(edge: .bottom) {
					TextField("Filter Files", text: $viewModel.filterText)
						.textFieldStyle(.roundedBorder)
						.padding(10)
						.background(.bar)
				}
			}
		}
	}

	@ViewBuilder
	private var conflictSection: some View {
		if !viewModel.filteredConflicts.isEmpty {
			Section {
				ForEach(viewModel.filteredConflicts) { conflict in
					ConflictRow(conflict: conflict) {
						conflictViewModel.didOpenInEditor(conflict)
					}
					.tag(WorkspaceChangeSelection.conflict(conflict.path))
					.listRowSeparator(.hidden)
					.contextMenu { conflictActions(conflict) }
				}
			} header: {
				ChangeListSectionHeader(title: "Conflicts", count: viewModel.filteredConflicts.count)
			}
		}
	}

	@ViewBuilder
	private var amendSection: some View {
		if commitViewModel.isAmendingCommit, !viewModel.amendChanges.isEmpty {
			Section {
				ForEach(viewModel.filteredAmendChanges) { change in
					AmendChangeRow(change: change) {
						viewModel.didRequestUnstageFromAmend([change])
					}
					.tag(WorkspaceChangeSelection.amend(change.id))
					.listRowSeparator(.hidden)
					.contextMenu { amendContextMenu(for: change) }
				}
			} header: {
				ChangeListSectionHeader(
					title: "Included in Amended Commit",
					count: viewModel.filteredAmendChanges.count
				)
			}
		}
	}

	@ViewBuilder
	private func workingTreeSection(
		title: String,
		changes: [WorkingTreeChange],
		source: GitDiffSource
	) -> some View {
		if !changes.isEmpty {
			Section {
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
					.contextMenu { changeContextMenu(for: change, source: source) }
				}
			} header: {
				ChangeListSectionHeader(title: title, count: changes.count)
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
		if source == .staged, !commitViewModel.isAmendingCommit {
			Button("Unstage Changes", systemImage: "minus.circle") {
				viewModel.didRequestUnstage(changes)
			}
			.disabled(viewModel.isLoading)
		}
		if source == .unstaged {
			Divider()
			Button("Discard Changes…", systemImage: "trash", role: .destructive) {
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
		Button(conflictViewModel.oursResolutionLabel, systemImage: "arrow.down.doc") {
			conflictViewModel.didResolve(conflict, using: .ours)
		}
		Button(conflictViewModel.theirsResolutionLabel, systemImage: "arrow.down.doc.fill") {
			conflictViewModel.didResolve(conflict, using: .theirs)
		}
		Divider()
		Button("Mark Resolved", systemImage: "checkmark.circle") {
			conflictViewModel.didMarkResolved(conflict)
		}
		Button("Open in Editor", systemImage: "square.and.pencil") {
			conflictViewModel.didOpenInEditor(conflict)
		}
		.disabled(!conflictFileExists(conflict))
	}

	private func conflictFileExists(_ conflict: GitConflict) -> Bool {
		guard let repositoryURL else { return false }
		return FileManager.default.fileExists(atPath: repositoryURL.appending(path: conflict.path).path)
	}

	private func contextChanges(
		for change: WorkingTreeChange,
		source: GitDiffSource
	) -> [WorkingTreeChange] {
		let selection = changeSelection(change, source: source)
		guard viewModel.selectedChangeIDs.contains(selection) else { return [change] }
		return source == .staged ? viewModel.selectedStagedChanges : viewModel.selectedUnstagedChanges
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
