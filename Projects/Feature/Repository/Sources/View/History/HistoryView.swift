import SwiftUI

struct HistoryView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.commitGraphItems.isEmpty {
				EmptyStateView(
					title: "No Commits",
					message: "Commit history will appear after the first commit.",
					systemImage: "point.3.connected.trianglepath.dotted"
				)
			} else {
				EqualWidthHSplitView(
					proportions: [0.36, 0.40, 0.24],
					minimumWidths: [280, 300, 210]
				) {
					historyList
						.frame(maxWidth: .infinity)
				} center: {
					CommitDiffView(
						file: viewModel.selectedCommitFile,
						changedFileCount: commitFiles.count,
						isLoading: viewModel.isLoadingCommitDiff
					)
					.id(viewModel.selectedCommitID)
					.frame(maxWidth: .infinity)
				} trailing: {
					CommitInspectorView(
						commit: viewModel.selectedCommit,
						files: commitFiles,
						isLoadingFiles: viewModel.isLoadingCommitDiff,
						remoteNames: remoteNames,
						selectedFileID: selectedCommitFileBinding
					)
					.frame(maxWidth: .infinity)
				}
			}
		}
		.navigationTitle(viewModel.repositoryName)
		.navigationSubtitle(viewModel.currentBranchStatus)
	}

	private var historyList: some View {
		ScrollViewReader { proxy in
			VStack(spacing: 0) {
				HStack(spacing: 8) {
					Image(systemName: "point.3.connected.trianglepath.dotted")
						.foregroundStyle(.secondary)
						.accessibilityHidden(true)
					Text("All Branches")
						.font(.subheadline.weight(.semibold))
					Spacer(minLength: 0)
				}
				.padding(.horizontal, 12)
				.frame(height: 44)
				.background(.bar)

				Divider()

				List(selection: selectedCommitBinding) {
					ForEach(viewModel.commitGraphItems) { item in
						CommitGraphRow(
							item: item,
							isSelected: item.id == viewModel.selectedCommitID,
							remoteNames: remoteNames
						)
						.equatable()
						.id(item.id)
						.tag(item.id)
						.contentShape(.rect)
						.listRowInsets(.init())
						.listRowSeparator(.hidden)
						.contextMenu {
							Button("Create Tag…", systemImage: "tag") {
								viewModel.didPresentNewTag(for: item.commit)
							}
						}
					}
				}
				.listStyle(.plain)
			}
			.task(id: viewModel.historyFocusRequest) {
				await scrollToFocusedCommit(using: proxy)
			}
		}
	}

	private var commitFiles: [CommitDiffFile] {
		viewModel.selectedCommitFiles
	}

	private var remoteNames: Set<String> {
		Set(viewModel.remotes.map(\.name))
	}

	private var selectedCommitBinding: Binding<String?> {
		Binding(
			get: { viewModel.selectedCommitID },
			set: { commitID in
				Task { await viewModel.didSelectCommit(commitID) }
			}
		)
	}

	private var selectedCommitFileBinding: Binding<CommitDiffFile.ID?> {
		Binding(
			get: { viewModel.selectedCommitFileID },
			set: { fileID in
				Task { await viewModel.didSelectCommitFile(fileID) }
			}
		)
	}

	private func scrollToFocusedCommit(using proxy: ScrollViewProxy) async {
		guard let request = viewModel.historyFocusRequest else { return }
		await Task.yield()
		guard !Task.isCancelled else { return }
		guard viewModel.commitGraphItems.contains(where: { $0.id == request.commitID }) else {
			return
		}

		if request.isAnimated && !reduceMotion {
			withAnimation(.easeInOut(duration: 0.2)) {
				proxy.scrollTo(request.commitID, anchor: .center)
			}
		} else {
			proxy.scrollTo(request.commitID, anchor: .center)
		}
	}
}
