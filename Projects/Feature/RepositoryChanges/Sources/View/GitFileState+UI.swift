import DomainGitInterface
import SwiftUI

extension GitFileState {
	var listSymbol: String {
		switch self {
		case .added, .copied, .untracked:
			return "A"
		case .deleted:
			return "D"
		case .modified:
			return "M"
		case .renamed:
			return "R"
		case .typeChanged:
			return "T"
		case .unmerged:
			return "U"
		case .ignored:
			return "!"
		case .unchanged:
			return ""
		}
	}

	var listColor: Color {
		switch self {
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

	var inspectorTitle: String {
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
}
