import DomainGitInterface
import SwiftUI

extension GitDiffHunkAction {
	var title: String {
		switch self {
		case .stage: return "Stage Hunk"
		case .unstage: return "Unstage Hunk"
		case .discard: return "Discard Hunk"
		}
	}

	var systemImage: String {
		switch self {
		case .stage: return "plus"
		case .unstage: return "minus"
		case .discard: return "trash"
		}
	}

	var isDestructive: Bool {
		self == .discard
	}
}
