import DomainGitInterface
import SwiftUI

extension GitDiffLineAction {
	var title: String {
		switch self {
		case .stage:
			return "Stage Line"
		case .unstage:
			return "Unstage Line"
		}
	}

	var systemImage: String {
		switch self {
		case .stage:
			return "plus"
		case .unstage:
			return "minus"
		}
	}

	var buttonTitle: String {
		switch self {
		case .stage:
			return "Stage"
		case .unstage:
			return "Unstage"
		}
	}

	var tint: Color {
		switch self {
		case .stage:
			return .accentColor
		case .unstage:
			return .orange
		}
	}
}
