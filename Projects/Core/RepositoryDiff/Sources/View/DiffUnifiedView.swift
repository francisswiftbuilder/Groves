import DomainGitInterface
import SwiftUI

struct DiffUnifiedView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let document: DiffDocument
	let filePath: String?
	@ObservedObject var searchModel: RepositorySearchViewModel
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isApplyingAction: Bool
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		GeometryReader { geometry in
			ScrollViewReader { proxy in
				ScrollView([.horizontal, .vertical]) {
					LazyVStack(alignment: .leading, spacing: 0) {
						ForEach(document.lines) { line in
							DiffLineView(
								line: line,
								filePath: filePath,
								searchText: searchModel.query,
								activeSearchRange: searchModel.activeRange(for: line.id),
								showsOldLineNumbers: document.showsOldLineNumbers,
								showsNewLineNumbers: document.showsNewLineNumbers,
								lineAction: lineAction,
								hunkActions: hunkActions,
								isLoading: isApplyingAction,
								onApplyLine: onApplyLine,
								onApplyHunk: onApplyHunk
							)
							.id(line.id)
						}
					}
					.textSelection(.enabled)
					.padding(.vertical, 8)
					.frame(minWidth: max(geometry.size.width, 0), alignment: .leading)
				}
				.defaultScrollAnchor(.topLeading)
				.onChange(of: searchModel.currentMatchID) { _, _ in
					guard let sourceID = searchModel.currentMatch?.sourceID else { return }
					if reduceMotion {
						proxy.scrollTo(sourceID, anchor: .center)
					} else {
						withAnimation(.easeInOut(duration: 0.15)) {
							proxy.scrollTo(sourceID, anchor: .center)
						}
					}
				}
			}
		}
	}
}
