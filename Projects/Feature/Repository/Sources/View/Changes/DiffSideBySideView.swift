import DomainGitInterface
import SwiftUI

struct DiffSideBySideView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let rows: [DiffSideBySideRow]
	let filePath: String?
	@ObservedObject var searchModel: RepositorySearchViewModel
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isApplyingAction: Bool
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		GeometryReader { geometry in
			let contentWidth = max(geometry.size.width, 668)
			let paneWidth = (contentWidth - 28) / 2

			ScrollViewReader { proxy in
				ScrollView([.horizontal, .vertical]) {
					LazyVStack(alignment: .leading, spacing: 0) {
						ForEach(rows) { row in
							DiffSideBySideRowView(
								row: row,
								paneWidth: paneWidth,
								filePath: filePath,
								searchText: searchModel.query,
								activeMatch: searchModel.currentMatch,
								lineAction: lineAction,
								hunkActions: hunkActions,
								isLoading: isApplyingAction,
								onApplyLine: onApplyLine,
								onApplyHunk: onApplyHunk
							)
							.id(row.id)
						}
					}
					.padding(.vertical, 8)
					.frame(width: contentWidth, alignment: .leading)
				}
				.defaultScrollAnchor(.topLeading)
				.onChange(of: searchModel.currentMatchID) { _, _ in
					guard let sourceID = searchModel.currentMatch?.sourceID,
						let row = rows.first(where: { $0.contains(lineID: sourceID) })
					else { return }
					if reduceMotion {
						proxy.scrollTo(row.id, anchor: .center)
					} else {
						withAnimation(.easeInOut(duration: 0.15)) {
							proxy.scrollTo(row.id, anchor: .center)
						}
					}
				}
			}
		}
	}
}
