import CoreRepositoryDiff
import CoreRepositoryUI
import DomainGitInterface
import SwiftUI

public struct StashesView: View {
	private let diffSearchViewModel: RepositorySearchViewModel
	private let stashesViewModel: StashesViewModel
	@Bindable private var diffPreferences: WorkspaceDiffPreferences
	let onDiffOptionsChanged: () -> Void

	public init(
		diffSearchViewModel: RepositorySearchViewModel,
		stashesViewModel: StashesViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		self.diffSearchViewModel = diffSearchViewModel
		self.stashesViewModel = stashesViewModel
		_diffPreferences = Bindable(wrappedValue: diffPreferences)
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	public var body: some View {
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
					.safeAreaInset(edge: .top, spacing: 0) {
						VStack(spacing: 0) {
							Text("Stashes").font(.headline)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.horizontal, 12)
								.frame(height: 52)
								.background(.bar)
							Divider()
						}
					}
				} center: {
					VStack(spacing: 0) {
						if stashesViewModel.isLoadingDiff {
							LoadingStateView(title: "Loading Stash Diff")
						} else {
							List(stashesViewModel.files, selection: fileSelection) { file in
								CommitChangedFileRow(file: file)
									.tag(file.id)
									.listRowSeparator(.hidden)
							}
							.listStyle(.plain)
						}
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.safeAreaInset(edge: .top, spacing: 0) {
						VStack(spacing: 0) {
							Text("Files").font(.subheadline.weight(.semibold))
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(.horizontal, 12)
								.frame(height: 52)
								.background(.bar)
							Divider()
						}
					}
				} trailing: {
					CommitDiffView(
						searchModel: diffSearchViewModel,
						options: $diffPreferences.options,
						presentationMode: $diffPreferences.presentationMode,
						file: stashesViewModel.selectedFile,
						imageDiff: stashesViewModel.imageDiff,
						beforeImageTitle: "Base",
						afterImageTitle: "Stash",
						changedFileCount: stashesViewModel.files.count,
						isLoading: stashesViewModel.isLoadingDiff
							|| stashesViewModel.isLoadingImageDiff,
						onOptionsChanged: onDiffOptionsChanged
					)
				}
			}
		}
		.safeAreaInset(edge: .bottom) {
			StashActionBar(viewModel: stashesViewModel) {
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
			if let stash = stashesViewModel.pendingDrop?.stash {
				Text("\(stash.reference) · \(stash.subject) will be permanently removed.")
			}
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
			set: { stashID in stashesViewModel.didSelectStash(stashID) }
		)
	}

	private var fileSelection: Binding<CommitDiffFile.ID?> {
		Binding(
			get: { stashesViewModel.selectedFileID },
			set: { fileID in stashesViewModel.didSelectFile(fileID) }
		)
	}
}
