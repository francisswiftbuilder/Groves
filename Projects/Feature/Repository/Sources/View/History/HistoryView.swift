import DomainGitInterface
import SwiftUI

struct HistoryView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject private var historyViewModel: HistoryViewModel
	@ObservedObject private var operationViewModel: RepositoryOperationViewModel
	@ObservedObject private var diffPreferences: WorkspaceDiffPreferences
	let repositoryName: String
	let currentBranchStatus: String
	let onDiffOptionsChanged: () -> Void

	init(
		historyViewModel: HistoryViewModel,
		operationViewModel: RepositoryOperationViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		repositoryName: String,
		currentBranchStatus: String,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		_historyViewModel = ObservedObject(wrappedValue: historyViewModel)
		_operationViewModel = ObservedObject(wrappedValue: operationViewModel)
		_diffPreferences = ObservedObject(wrappedValue: diffPreferences)
		self.repositoryName = repositoryName
		self.currentBranchStatus = currentBranchStatus
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	var body: some View {
		Group {
			if historyViewModel.commitGraphItems.isEmpty {
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
						options: $diffPreferences.options,
						presentationMode: $diffPreferences.presentationMode,
						file: historyViewModel.selectedCommitFile,
						imageDiff: historyViewModel.commitImageDiff,
						beforeImageTitle: "Parent",
						afterImageTitle: "Commit",
						changedFileCount: commitFiles.count,
						isLoading: historyViewModel.isLoadingCommitDiff
							|| historyViewModel.isLoadingCommitImageDiff,
						onOptionsChanged: onDiffOptionsChanged
					)
					.id(historyViewModel.selectedCommitID)
					.frame(maxWidth: .infinity)
				} trailing: {
					CommitInspectorView(
						commit: historyViewModel.selectedCommit,
						files: commitFiles,
						isLoadingFiles: historyViewModel.isLoadingCommitDiff,
						remoteNames: remoteNames,
						selectedFileID: selectedCommitFileBinding
					)
					.frame(maxWidth: .infinity)
				}
			}
		}
		.navigationTitle(repositoryName)
		.navigationSubtitle(currentBranchStatus)
	}

	private var historyList: some View {
		ScrollViewReader { proxy in
			VStack(spacing: 0) {
				VStack(spacing: 8) {
					HStack(spacing: 8) {
						Image(systemName: "point.3.connected.trianglepath.dotted")
							.foregroundStyle(.secondary)
							.accessibilityHidden(true)
						Text("All Branches")
							.font(.subheadline.weight(.semibold))
						Spacer(minLength: 0)
					}

					TextField(
						"Search commits",
						text: Binding(
							get: { historyViewModel.searchText },
							set: { historyViewModel.didChangeSearchText($0) }
						)
					)
					.textFieldStyle(.roundedBorder)
					.accessibilityLabel("Search commit history")
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(.bar)

				Divider()

				List(selection: selectedCommitBinding) {
					if historyViewModel.displayedCommitGraphItems.isEmpty {
						ContentUnavailableView.search(text: historyViewModel.searchText)
							.listRowSeparator(.hidden)
					} else {
						ForEach(historyViewModel.displayedCommitGraphItems) { item in
							CommitGraphRow(
								item: item,
								isSelected: item.id == historyViewModel.selectedCommitID,
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
								.disabled(
									!operationViewModel.operationState.isIdle
										|| operationViewModel.operationState.isDetached
										|| operationViewModel.isLoading
								)

								Button("Revert", systemImage: "arrow.uturn.backward") {
									request(.revert(item.commit))
								}
								.disabled(
									!operationViewModel.operationState.isIdle
										|| operationViewModel.operationState.isDetached
										|| operationViewModel.isLoading
								)

								Button("Create Branch from Commit…", systemImage: "arrow.triangle.branch") {
									operationViewModel.didPresentNewBranch(from: item.commit)
								}
								.disabled(!operationViewModel.operationState.isIdle || operationViewModel.isLoading)

								Button("Checkout Commit…", systemImage: "scope") {
									operationViewModel.didPresentCheckoutCommit(item.commit)
								}
								.disabled(!operationViewModel.canCheckoutCommit)

								Button("Create Tag…", systemImage: "tag") {
									operationViewModel.didPresentNewTag(for: item.commit)
								}

								Divider()

								Button("Reset Current Branch to…", systemImage: "arrow.counterclockwise") {
									operationViewModel.didPresentReset(item.commit)
								}
								.disabled(
									!operationViewModel.operationState.isIdle
										|| operationViewModel.operationState.isDetached
										|| operationViewModel.isLoading
								)
							}
						}
					}
				}
				.listStyle(.plain)
			}
			.task(id: historyViewModel.historyFocusRequest) {
				await scrollToFocusedCommit(using: proxy)
			}
		}
	}

	private var commitFiles: [CommitDiffFile] {
		historyViewModel.selectedCommitFiles
	}

	private var remoteNames: Set<String> {
		Set(operationViewModel.remotes.map(\.name))
	}

	private var selectedCommitBinding: Binding<String?> {
		Binding(
			get: { historyViewModel.selectedCommitID },
			set: { commitID in
				Task { await historyViewModel.didSelectCommit(commitID) }
			}
		)
	}

	private var selectedCommitFileBinding: Binding<CommitDiffFile.ID?> {
		Binding(
			get: { historyViewModel.selectedCommitFileID },
			set: { fileID in
				Task { await historyViewModel.didSelectCommitFile(fileID) }
			}
		)
	}

	private func scrollToFocusedCommit(using proxy: ScrollViewProxy) async {
		guard let request = historyViewModel.historyFocusRequest else { return }
		await Task.yield()
		guard !Task.isCancelled else { return }
		guard
			historyViewModel.displayedCommitGraphItems.contains(where: { $0.id == request.commitID })
		else {
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
		operationViewModel.didPresentCommitAction(action)
	}
}
