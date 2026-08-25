import DomainGitInterface
import SwiftUI

struct StashesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var selectedFileID: CommitDiffFile.ID?
	@State private var parsedFiles: [CommitDiffFile] = []

	var body: some View {
		Group {
			if viewModel.stashes.isEmpty {
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
						ForEach(viewModel.stashes) { stash in
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
						options: $viewModel.diffOptions,
						presentationMode: $viewModel.diffPresentationMode,
						file: selectedFile,
						imageDiff: viewModel.stashImageDiff,
						beforeImageTitle: "Base",
						afterImageTitle: "Stash",
						changedFileCount: files.count,
						isLoading: viewModel.isLoadingStashImageDiff,
						onOptionsChanged: viewModel.didChangeDiffOptions
					)
				}
			}
		}
		.navigationTitle("Stashes")
		.navigationSubtitle("\(viewModel.stashes.count) stashes")
		.safeAreaInset(edge: .bottom) {
			StashActionBar(viewModel: viewModel) {
				if let stash = viewModel.selectedStash {
					viewModel.didPresentStashDrop(stash)
				}
			}
		}
		.task(id: viewModel.stashDiff) {
			let diff = viewModel.stashDiff
			let files = await Task.detached(priority: .userInitiated) {
				CommitDiffFileParser.parse(diff)
			}.value
			guard !Task.isCancelled else { return }
			parsedFiles = files
			if !files.contains(where: { $0.id == selectedFileID }) {
				selectedFileID = files.first?.id
			}
			viewModel.didSelectStashFile(selectedFile)
		}
	}

	private var stashSelection: Binding<String?> {
		Binding(
			get: { viewModel.selectedStashID },
			set: { stashID in
				selectedFileID = nil
				viewModel.didSelectStash(stashID)
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
				viewModel.didSelectStashFile(
					files.first { $0.id == fileID } ?? files.first
				)
			}
		)
	}
}
