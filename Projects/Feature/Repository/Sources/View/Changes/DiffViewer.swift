import DomainGitInterface
import FeatureRepositoryInterface
import SwiftUI

struct DiffViewer: View {
	@StateObject private var searchModel = RepositorySearchViewModel()
	let document: DiffDocument
	let sideBySideRows: [DiffSideBySideRow]
	let presentationMode: DiffPresentationMode
	let filePath: String?
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isApplyingAction: Bool
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		Group {
			switch presentationMode {
			case .sideBySide:
				DiffSideBySideView(
					rows: sideBySideRows,
					filePath: filePath,
					searchModel: searchModel,
					lineAction: lineAction,
					hunkActions: hunkActions,
					isApplyingAction: isApplyingAction,
					onApplyLine: onApplyLine,
					onApplyHunk: onApplyHunk
				)
			case .unified:
				DiffUnifiedView(
					document: document,
					filePath: filePath,
					searchModel: searchModel,
					lineAction: lineAction,
					hunkActions: hunkActions,
					isApplyingAction: isApplyingAction,
					onApplyLine: onApplyLine,
					onApplyHunk: onApplyHunk
				)
			}
		}
		.safeAreaInset(edge: .top) {
			if searchModel.isPresented {
				RepositoryFindBar(model: searchModel, prompt: "Find in Diff")
			}
		}
		.focusedSceneValue(\.repositoryFindActions, searchModel)
		.onAppear { updateSearchSources() }
		.onChange(of: document) { _, _ in updateSearchSources() }
	}

	private func updateSearchSources() {
		searchModel.update(
			sources: document.lines.map {
				RepositorySearchSource(id: $0.id, text: $0.sourceText)
			}
		)
	}
}

#Preview {
	let diff = """
		@@ -1,2 +1,2 @@
		-let timeout = 30
		+let timeout = 60
		 context
		"""
	DiffViewer(
		document: DiffDocument(lines: DiffParser.parse(diff)),
		sideBySideRows: DiffSideBySideBuilder.build(
			from: DiffDocument(lines: DiffParser.parse(diff))
		),
		presentationMode: .sideBySide,
		filePath: "Sources/App.swift",
		lineAction: .stage,
		hunkActions: [.stage, .discard],
		isApplyingAction: false,
		onApplyLine: { _, _ in },
		onApplyHunk: { _, _ in }
	)
	.frame(width: 720, height: 360)
}
