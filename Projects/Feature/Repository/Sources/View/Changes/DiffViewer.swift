import DomainGitInterface
import FeatureRepositoryInterface
import SwiftUI

struct DiffViewer: View {
	@State private var isSearchPresented = false
	@State private var searchText = ""
	let document: DiffDocument
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
					rows: DiffSideBySideBuilder.build(from: document),
					filePath: filePath,
					searchText: searchText,
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
					searchText: searchText,
					lineAction: lineAction,
					hunkActions: hunkActions,
					isApplyingAction: isApplyingAction,
					onApplyLine: onApplyLine,
					onApplyHunk: onApplyHunk
				)
			}
		}
		.searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Find in Diff")
		.focusedSceneValue(\.repositoryFindPresentation, $isSearchPresented)
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
