import DomainGitInterface

enum PendingMainlineAction: Identifiable {
	case cherryPick(GitCommit)
	case revert(GitCommit)

	var id: String {
		switch self {
		case .cherryPick(let commit): return "cherry-pick-\(commit.id)"
		case .revert(let commit): return "revert-\(commit.id)"
		}
	}

	var commit: GitCommit {
		switch self {
		case .cherryPick(let commit), .revert(let commit): return commit
		}
	}

	var title: String {
		switch self {
		case .cherryPick: return "Cherry-pick Merge Commit"
		case .revert: return "Revert Merge Commit"
		}
	}
}
