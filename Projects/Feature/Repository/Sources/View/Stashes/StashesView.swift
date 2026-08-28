import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import FeatureRepositoryChanges
import FeatureRepositoryInterface
import SwiftUI

struct StashesView: View {
	@ObservedObject private var changesViewModel: ChangesViewModel
	@ObservedObject private var stashesViewModel: StashesViewModel
	@ObservedObject private var diffPreferences: WorkspaceDiffPreferences
	@State private var selectedFileID: CommitDiffFile.ID?
	@State private var parsedFiles: [CommitDiffFile] = []
	let onDiffOptionsChanged: () -> Void

	init(
		changesViewModel: ChangesViewModel,
		stashesViewModel: StashesViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		_changesViewModel = ObservedObject(wrappedValue: changesViewModel)
		_stashesViewModel = ObservedObject(wrappedValue: stashesViewModel)
		_diffPreferences = ObservedObject(wrappedValue: diffPreferences)
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	var body: some View {
		Group {
			if stashesViewModel.stashes.isEmpty {
				EmptyStateView(
					title: "No Stashes",
					message: "Save uncommitted changes to return to them later.",
					systemImage: "archivebox"
				)
			} else {
				EqualWidthHSplitView(
					proportions: [0.30, 0.30, 0.40],
					minimumWidths: [220, 220, 300]
				) {
					List(selection: stashSelection) {
						ForEach(stashesViewModel.stashes) { stash in
							StashRow(stash: stash)
								.tag(stash.id)
								.listRowSeparator(.hidden)
						}
					}
					.listStyle(.inset)
				} center: {
					List(files, selection: selectedFileBinding) { file in
						CommitChangedFileRow(file: file)
							.tag(file.id)
							.listRowSeparator(.hidden)
					}
					.listStyle(.plain)
				} trailing: {
					CommitDiffView(
						options: $diffPreferences.options,
						presentationMode: $diffPreferences.presentationMode,
						file: selectedFile,
						imageDiff: stashesViewModel.imageDiff,
						beforeImageTitle: "Base",
						afterImageTitle: "Stash",
						changedFileCount: files.count,
						isLoading: stashesViewModel.isLoadingImageDiff,
						onOptionsChanged: onDiffOptionsChanged
					)
				}
			}
		}
		.navigationTitle("Stashes")
		.navigationSubtitle("\(stashesViewModel.stashes.count) stashes")
		.safeAreaInset(edge: .bottom) {
			StashActionBar(viewModel: stashesViewModel, changesViewModel: changesViewModel) {
				if let stash = stashesViewModel.selectedStash {
					stashesViewModel.didPresentStashDrop(stash)
				}
			}
		}
		.confirmationDialog(
			"Delete Stash",
			isPresented: pendingDropPresentation
		) {
			Button("Delete Stash", role: .destructive) {
				stashesViewModel.didConfirmStashDrop()
			}
			Button("Cancel", role: .cancel) {
				stashesViewModel.didDismissStashDrop()
			}
		} message: {
			if let stash = stashesViewModel.pendingDrop {
				Text("\(stash.reference) · \(stash.subject) will be permanently removed.")
			}
		}
		.task(id: stashesViewModel.diff) {
			let diff = stashesViewModel.diff
			let files = await Task.detached(priority: .userInitiated) {
				CommitDiffFileParser.parse(diff)
			}.value
			guard !Task.isCancelled else { return }
			parsedFiles = files
			if !files.contains(where: { $0.id == selectedFileID }) {
				selectedFileID = files.first?.id
			}
			stashesViewModel.didSelectStashFile(selectedFile)
		}
	}

	private var pendingDropPresentation: Binding<Bool> {
		Binding(
			get: { stashesViewModel.pendingDrop != nil },
			set: { isPresented in
				if !isPresented {
					stashesViewModel.didDismissStashDrop()
				}
			}
		)
	}

	private var stashSelection: Binding<String?> {
		Binding(
			get: { stashesViewModel.selectedStashID },
			set: { stashID in
				selectedFileID = nil
				stashesViewModel.didSelectStash(stashID)
			}
		)
	}

	private var files: [CommitDiffFile] {
		parsedFiles
	}

	private var selectedFile: CommitDiffFile? {
		files.first { $0.id == selectedFileID } ?? files.first
	}

	private var selectedFileBinding: Binding<CommitDiffFile.ID?> {
		Binding(
			get: { selectedFileID },
			set: { fileID in
				selectedFileID = fileID
				stashesViewModel.didSelectStashFile(
					files.first { $0.id == fileID } ?? files.first
				)
			}
		)
	}
}
