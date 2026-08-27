public enum WorkspaceSection: String, CaseIterable, Identifiable, Sendable {
	case changes
	case history
	case branches
	case remotes
	case stashes
	case tree

	public var id: String { rawValue }

	public var title: String {
		switch self {
		case .changes:
			return "Changes"
		case .history:
			return "History"
		case .branches:
			return "Branches"
		case .remotes:
			return "Remotes"
		case .stashes:
			return "Stashes"
		case .tree:
			return "Workspace"
		}
	}

	public var systemImage: String {
		switch self {
		case .changes:
			return "arrow.triangle.2.circlepath"
		case .history:
			return "clock"
		case .branches:
			return "arrow.triangle.branch"
		case .remotes:
			return "icloud"
		case .stashes:
			return "archivebox"
		case .tree:
			return "folder"
		}
	}
}
