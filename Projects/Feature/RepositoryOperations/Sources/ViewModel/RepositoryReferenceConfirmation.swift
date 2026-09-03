import DomainGitInterface

enum RepositoryReferenceConfirmation {
	case deleteBranch(GitBranch)
	case deleteTag(GitTag)
	case checkoutCommit(GitCommit)

	var title: String {
		switch self {
		case .deleteBranch(let branch): return "Delete “\(branch.name)”"
		case .deleteTag(let tag): return "Delete “\(tag.name)”"
		case .checkoutCommit(let commit):
			return "Checkout \(commit.shortHash) in Detached HEAD?"
		}
	}

	var message: String {
		switch self {
		case .deleteBranch(let branch):
			return "The local branch “\(branch.name)” will be deleted. Remote branches are not affected."
		case .deleteTag(let tag):
			return "The local tag “\(tag.name)” will be deleted. Remote tags are not affected."
		case .checkoutCommit(let commit):
			return
				"You will leave the current branch and inspect \(commit.shortHash). Create or switch to a branch to keep new work."
		}
	}

	var actionTitle: String {
		switch self {
		case .deleteBranch: return "Delete Branch"
		case .deleteTag: return "Delete Tag"
		case .checkoutCommit: return "Checkout Commit"
		}
	}
}
