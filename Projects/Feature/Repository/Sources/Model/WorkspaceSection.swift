enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
	case changes
	case history
	case branches
	case tags
	case tree

	var id: String { rawValue }

	var title: String {
		switch self {
		case .changes:
			return "Changes"
		case .history:
			return "History"
		case .branches:
			return "Branches"
		case .tags:
			return "Tags"
		case .tree:
			return "Tree"
		}
	}

	var systemImage: String {
		switch self {
		case .changes:
			return "arrow.triangle.2.circlepath"
		case .history:
			return "clock"
		case .branches:
			return "arrow.triangle.branch"
		case .tags:
			return "tag"
		case .tree:
			return "folder"
		}
	}
}
