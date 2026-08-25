import DomainGitInterface
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
						options: $viewModel.diffOptions,
						presentationMode: $viewModel.diffPresentationMode,
						file: viewModel.selectedCommitFile,
						imageDiff: viewModel.commitImageDiff,
						beforeImageTitle: "Parent",
						afterImageTitle: "Commit",
						changedFileCount: commitFiles.count,
						isLoading: viewModel.isLoadingCommitDiff
							|| viewModel.isLoadingCommitImageDiff,
						onOptionsChanged: viewModel.didChangeDiffOptions
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
							Button("Cherry-pick", systemImage: "arrow.triangle.branch") {
								request(.cherryPick(item.commit))
							}
							.disabled(!viewModel.operationState.isIdle || viewModel.isLoading)

							Button("Revert", systemImage: "arrow.uturn.backward") {
								request(.revert(item.commit))
							}
							.disabled(!viewModel.operationState.isIdle || viewModel.isLoading)

							Button("Create Tag…", systemImage: "tag") {
								viewModel.didPresentNewTag(for: item.commit)
							}

							Divider()

							Button("Reset Current Branch to…", systemImage: "arrow.counterclockwise") {
								viewModel.didPresentReset(item.commit)
							}
							.disabled(
								!viewModel.operationState.isIdle
									|| viewModel.operationState.isDetached
									|| viewModel.isLoading
							)
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

	private func request(_ action: PendingMainlineAction) {
		viewModel.didPresentCommitAction(action)
	}
}
