import CoreRepositoryUI
import DomainGitInterface
import FeatureRepositoryDiff
import FeatureRepositoryInterface
import SwiftUI

struct ConflictPreview: View {
	@ObservedObject private var viewModel: ConflictViewModel
	@StateObject private var searchModel = RepositorySearchViewModel()
	let repositoryURL: URL?
	let conflict: GitConflict

	init(
		viewModel: ConflictViewModel,
		repositoryURL: URL?,
		conflict: GitConflict
	) {
		_viewModel = ObservedObject(wrappedValue: viewModel)
		self.repositoryURL = repositoryURL
		self.conflict = conflict
	}

	var body: some View {
		conflictContent
			.safeAreaInset(edge: .top) {
				conflictHeader
			}
			.focusedSceneValue(\.repositoryFindActions, searchModel)
			.onAppear { updateSearchSources() }
			.onChange(of: viewModel.content) { _, _ in updateSearchSources() }
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

				if let hunkCount = viewModel.content?.hunks.count, hunkCount > 0 {
					Text("\(hunkCount) conflicts")
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
				}

				Button("Mark Resolved") {
					viewModel.didMarkResolved(conflict)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
				.disabled(viewModel.isLoading)

				Menu("File Actions", systemImage: "ellipsis.circle") {
					Button(currentFileResolutionTitle, systemImage: "arrow.down.doc") {
						viewModel.didResolve(conflict, using: .ours)
					}
					Button(incomingFileResolutionTitle, systemImage: "arrow.down.doc.fill") {
						viewModel.didResolve(conflict, using: .theirs)
					}
					Divider()
					Button("Open in Editor", systemImage: "square.and.pencil") {
						viewModel.didOpenInEditor(conflict)
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

			if searchModel.isPresented {
				RepositoryFindBar(model: searchModel, prompt: "Find in Conflict")
			}
		}
	}

	@ViewBuilder
	private var conflictContent: some View {
		if viewModel.isLoadingContent {
			LoadingStateView(
				title: "Loading Conflict",
				message: "Reading the current, incoming, and working versions."
			)
		} else if let content = viewModel.content {
			if DiffImageFileSupport.isSupported(path: conflict.path) {
				ImageDiffView(
					diff: GitImageDiff(
						before: content.currentData,
						after: content.incomingData
					),
					beforeTitle: viewModel.currentLabel,
					afterTitle: viewModel.incomingLabel
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
									currentLabel: viewModel.currentLabel,
									incomingLabel: viewModel.incomingLabel,
									filePath: conflict.path,
									searchText: searchModel.query,
									isLoading: viewModel.isLoading,
									onResolve: { resolution in
										viewModel.didResolve(
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
										searchText: searchModel.query,
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
				currentLabel: viewModel.currentLabel,
				currentContent: content.current,
				incomingLabel: viewModel.incomingLabel,
				incomingContent: content.incoming,
				filePath: conflict.path,
				searchText: searchModel.query,
				currentUnavailableMessage: "File deleted in \(viewModel.currentLabel.lowercased())",
				incomingUnavailableMessage:
					"File deleted in \(viewModel.incomingLabel.lowercased())"
			)
		}
	}

	private var canOpenInEditor: Bool {
		guard let repositoryURL else { return false }
		return FileManager.default.fileExists(atPath: repositoryURL.appending(path: conflict.path).path)
	}

	private func updateSearchSources() {
		guard let content = viewModel.content else {
			searchModel.update(sources: [])
			return
		}
		var values: [String] = []
		if content.hunks.isEmpty {
			values.append(contentsOf: [content.current, content.incoming].compactMap { $0 })
		} else {
			for hunk in content.hunks {
				values.append(hunk.current)
				values.append(hunk.incoming)
				if let base = hunk.base {
					values.append(base)
				}
			}
			if let base = content.base {
				values.append(base)
			}
		}
		searchModel.update(
			sources: values.enumerated().map {
				RepositorySearchSource(id: $0.offset, text: $0.element)
			}
		)
	}

	private var currentFileResolutionTitle: String {
		if !conflict.hasOurs {
			return "Delete File"
		}
		if !conflict.hasTheirs {
			return "Keep File"
		}
		return viewModel.oursResolutionLabel
	}

	private var incomingFileResolutionTitle: String {
		if !conflict.hasTheirs {
			return "Delete File"
		}
		if !conflict.hasOurs {
			return "Keep File"
		}
		return viewModel.theirsResolutionLabel
	}
}
