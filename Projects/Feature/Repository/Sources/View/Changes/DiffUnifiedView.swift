import DomainGitInterface
import SwiftUI

struct DiffUnifiedView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let document: DiffDocument
	let filePath: String?
	let searchText: String
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
								searchText: searchText,
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
				.onChange(of: searchText) { _, searchText in
					guard let line = firstMatchingLine(searchText) else { return }
					if reduceMotion {
						proxy.scrollTo(line.id, anchor: .center)
					} else {
						withAnimation(.easeInOut(duration: 0.15)) {
							proxy.scrollTo(line.id, anchor: .center)
						}
					}
				}
			}
		}
	}

	private func firstMatchingLine(_ searchText: String) -> DiffLine? {
		guard !searchText.isEmpty else { return nil }
		return document.lines.first {
			$0.sourceText.localizedCaseInsensitiveContains(searchText)
		}
	}
}
