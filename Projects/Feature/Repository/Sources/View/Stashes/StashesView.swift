import DomainGitInterface
import SwiftUI

struct StashesView: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var selectedFileID: CommitDiffFile.ID?

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
					List(files, selection: $selectedFileID) { file in
						CommitChangedFileRow(file: file)
							.tag(file.id)
							.listRowSeparator(.hidden)
					}
					.listStyle(.plain)
				} trailing: {
					CommitDiffView(
						file: selectedFile,
						changedFileCount: files.count,
						isLoading: false
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
		CommitDiffFileParser.parse(viewModel.stashDiff)
	}

	private var selectedFile: CommitDiffFile? {
		files.first { $0.id == selectedFileID } ?? files.first
	}
}
