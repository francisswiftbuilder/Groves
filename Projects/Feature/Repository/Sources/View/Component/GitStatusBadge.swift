import DomainGitInterface
import SwiftUI

struct GitStatusBadge: View {
	let state: GitFileState

	var body: some View {
		Text(state.symbol)
			.font(.system(.caption2, design: .rounded, weight: .bold))
			.foregroundStyle(color)
			.frame(width: 20, height: 20)
			.background {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(color.opacity(0.12))
			}
			.accessibilityLabel(state.title)
	}

	private var color: Color {
		switch state {
		case .added, .copied, .untracked:
			return .green
		case .deleted:
			return .red
		case .modified, .renamed, .typeChanged:
			return .orange
		case .unmerged:
			return .purple
		case .ignored, .unchanged:
			return .secondary
		}
	}
}

extension GitFileState {
	var title: String {
		switch self {
		case .added:
			return "Added"
		case .copied:
			return "Copied"
		case .deleted:
			return "Deleted"
		case .ignored:
			return "Ignored"
		case .modified:
			return "Modified"
		case .renamed:
			return "Renamed"
		case .typeChanged:
			return "Type Changed"
		case .unmerged:
			return "Unmerged"
		case .untracked:
			return "Untracked"
		case .unchanged:
			return "Unchanged"
		}
	}

	var symbol: String {
		switch self {
		case .added:
			return "A"
		case .copied:
			return "C"
		case .deleted:
			return "D"
		case .ignored:
			return "!"
		case .modified:
			return "M"
		case .renamed:
			return "R"
		case .typeChanged:
			return "T"
		case .unmerged:
			return "U"
		case .untracked:
			return "?"
		case .unchanged:
			return " "
		}
	}
}
