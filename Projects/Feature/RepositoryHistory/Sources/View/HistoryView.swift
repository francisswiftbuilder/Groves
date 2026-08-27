import DomainGitInterface
import FeatureRepositoryDiff
import FeatureRepositoryInterface
import FeatureRepositoryUI
import SwiftUI

public struct HistoryView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject private var historyViewModel: HistoryViewModel
	@ObservedObject private var diffPreferences: WorkspaceDiffPreferences
	let repositoryName: String
	let currentBranchStatus: String
	let operationState: RepositoryOperationState
	let isOperationLoading: Bool
	let canCheckoutCommit: Bool
	let remoteNames: Set<String>
	let commitActions: RepositoryCommitActions
	let onDiffOptionsChanged: () -> Void

	public init(
		historyViewModel: HistoryViewModel,
		diffPreferences: WorkspaceDiffPreferences,
		repositoryName: String,
		currentBranchStatus: String,
		operationState: RepositoryOperationState,
		isOperationLoading: Bool,
		canCheckoutCommit: Bool,
		remoteNames: Set<String>,
		commitActions: RepositoryCommitActions,
		onDiffOptionsChanged: @escaping () -> Void
	) {
		_historyViewModel = ObservedObject(wrappedValue: historyViewModel)
		_diffPreferences = ObservedObject(wrappedValue: diffPreferences)
		self.repositoryName = repositoryName
		self.currentBranchStatus = currentBranchStatus
		self.operationState = operationState
		self.isOperationLoading = isOperationLoading
		self.canCheckoutCommit = canCheckoutCommit
		self.remoteNames = remoteNames
		self.commitActions = commitActions
		self.onDiffOptionsChanged = onDiffOptionsChanged
	}

	public var body: some View {
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
									commitActions.cherryPick(item.commit)
								}
								.disabled(
									!operationState.isIdle
										|| operationState.isDetached
										|| isOperationLoading
								)

								Button("Revert", systemImage: "arrow.uturn.backward") {
									commitActions.revert(item.commit)
								}
								.disabled(
									!operationState.isIdle
										|| operationState.isDetached
										|| isOperationLoading
								)

								Button("Create Branch from Commit…", systemImage: "arrow.triangle.branch") {
									commitActions.createBranch(item.commit)
								}
								.disabled(!operationState.isIdle || isOperationLoading)

								Button("Checkout Commit…", systemImage: "scope") {
									commitActions.checkoutCommit(item.commit)
								}
								.disabled(!canCheckoutCommit)

								Button("Create Tag…", systemImage: "tag") {
									commitActions.createTag(item.commit)
								}

								Divider()

								Button("Reset Current Branch to…", systemImage: "arrow.counterclockwise") {
									commitActions.reset(item.commit)
								}
								.disabled(
									!operationState.isIdle
										|| operationState.isDetached
										|| isOperationLoading
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
}
