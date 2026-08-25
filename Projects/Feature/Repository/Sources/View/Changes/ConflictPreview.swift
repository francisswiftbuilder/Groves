import DomainGitInterface
import FeatureRepositoryInterface
import SwiftUI

struct ConflictPreview: View {
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var isSearchPresented = false
	@State private var searchText = ""
	let conflict: GitConflict

	var body: some View {
		conflictContent
			.safeAreaInset(edge: .top) {
				conflictHeader
			}
			.searchable(
				text: $searchText,
				isPresented: $isSearchPresented,
				prompt: "Find in Conflict"
			)
			.focusedSceneValue(\.repositoryFindPresentation, $isSearchPresented)
	}

	private var conflictHeader: some View {
		VStack(spacing: 0) {
			HStack(spacing: 10) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 2) {
					Text(URL(fileURLWithPath: conflict.path).lastPathComponent)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					Text(conflict.path)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				Spacer(minLength: 12)

				if let hunkCount = viewModel.conflictContent?.hunks.count, hunkCount > 0 {
					Text("\(hunkCount) conflicts")
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
				}

				Button("Mark Resolved") {
					viewModel.didMarkConflictResolved(conflict)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				.disabled(viewModel.isLoading)

				Menu("File Actions", systemImage: "ellipsis.circle") {
					Button(currentFileResolutionTitle, systemImage: "arrow.down.doc") {
						viewModel.didResolveConflict(conflict, using: .ours)
					}
					Button(incomingFileResolutionTitle, systemImage: "arrow.down.doc.fill") {
						viewModel.didResolveConflict(conflict, using: .theirs)
					}
					Divider()
					Button("Open in Editor", systemImage: "square.and.pencil") {
						viewModel.didOpenConflictInEditor(conflict)
					}
					.disabled(!canOpenInEditor)
				}
				.menuStyle(.borderlessButton)
				.fixedSize()
				.help("File Actions")
			}
			.padding(.horizontal, 12)
			.frame(minHeight: 52)
			.background(.bar)
			Divider()
		}
	}

	@ViewBuilder
	private var conflictContent: some View {
		if viewModel.isLoadingDiff {
			LoadingStateView(
				title: "Loading Conflict",
				message: "Reading the current, incoming, and working versions."
			)
		} else if let content = viewModel.conflictContent {
			if DiffImageFileSupport.isSupported(path: conflict.path) {
				ImageDiffView(
					diff: GitImageDiff(
						before: content.currentData,
						after: content.incomingData
					),
					beforeTitle: viewModel.currentConflictLabel,
					afterTitle: viewModel.incomingConflictLabel
				)
			} else {
				ScrollView(.vertical) {
					LazyVStack(alignment: .leading, spacing: 12) {
						if content.hunks.isEmpty {
							fileComparison(content)
						} else {
							ForEach(Array(content.hunks.enumerated()), id: \.element.id) { index, hunk in
								ConflictHunkView(
									hunk: hunk,
									position: index + 1,
									count: content.hunks.count,
									currentLabel: viewModel.currentConflictLabel,
									incomingLabel: viewModel.incomingConflictLabel,
									filePath: conflict.path,
									searchText: searchText,
									isLoading: viewModel.isLoading,
									onResolve: { resolution in
										viewModel.didResolveConflictHunk(
											hunk,
											in: conflict,
											using: resolution
										)
									}
								)
							}

							if let base = content.base {
								DisclosureGroup("Base Version") {
									ConflictCodeSection(
										title: "Base",
										content: base,
										filePath: conflict.path,
										searchText: searchText,
										unavailableMessage: "Base unavailable"
									)
								}
							}
						}
					}
					.padding(12)
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				.defaultScrollAnchor(.topLeading)
			}
		} else {
			ContentUnavailableView(
				"Preview Unavailable",
				systemImage: "doc.questionmark",
				description: Text("The conflicted file is binary or unavailable.")
			)
		}
	}

	private func fileComparison(_ content: GitConflictContent) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Label(
				"Compare both versions, then resolve the entire file or edit the result manually.",
				systemImage: "arrow.triangle.merge"
			)
			.font(.callout)
			.foregroundStyle(.secondary)

			ConflictSideBySideComparison(
				currentLabel: viewModel.currentConflictLabel,
				currentContent: content.current,
				incomingLabel: viewModel.incomingConflictLabel,
				incomingContent: content.incoming,
				filePath: conflict.path,
				searchText: searchText,
				currentUnavailableMessage: "File deleted in \(viewModel.currentConflictLabel.lowercased())",
				incomingUnavailableMessage:
					"File deleted in \(viewModel.incomingConflictLabel.lowercased())"
			)
		}
	}

	private var canOpenInEditor: Bool {
		guard let repositoryURL = viewModel.repositoryURL else { return false }
		return FileManager.default.fileExists(atPath: repositoryURL.appending(path: conflict.path).path)
	}

	private var currentFileResolutionTitle: String {
		if !conflict.hasOurs {
			return "Delete File"
		}
		if !conflict.hasTheirs {
			return "Keep File"
		}
		return viewModel.oursConflictLabel
	}

	private var incomingFileResolutionTitle: String {
		if !conflict.hasTheirs {
			return "Delete File"
		}
		if !conflict.hasOurs {
			return "Keep File"
		}
		return viewModel.theirsConflictLabel
	}
}
