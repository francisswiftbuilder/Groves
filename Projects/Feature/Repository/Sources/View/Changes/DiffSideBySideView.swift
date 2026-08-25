import DomainGitInterface
import SwiftUI

struct DiffSideBySideView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let rows: [DiffSideBySideRow]
	let filePath: String?
	let searchText: String
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
								searchText: searchText,
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
				.onChange(of: searchText) { _, searchText in
					guard let row = firstMatchingRow(searchText) else { return }
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

	private func firstMatchingRow(_ searchText: String) -> DiffSideBySideRow? {
		guard !searchText.isEmpty else { return nil }
		return rows.first {
			$0.searchableText.localizedCaseInsensitiveContains(searchText)
		}
	}
}
