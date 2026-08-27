import DomainGitInterface

enum RepositoryRemoteConfirmation {
	case deleteRemote(GitRemote)
	case deleteRemoteBranch(GitRemoteBranch)

	var title: String {
		switch self {
		case .deleteRemote:
			return "Delete Remote"
		case .deleteRemoteBranch:
			return "Delete Remote Branch"
		}
	}

	var message: String {
		switch self {
		case .deleteRemote(let remote):
			return
				"The local configuration for \(remote.name) will be removed. The remote repository is not deleted."
		case .deleteRemoteBranch(let branch):
			return "\(branch.fullName) will be deleted from \(branch.remoteName) for all collaborators."
		}
	}

	var actionTitle: String {
		switch self {
		case .deleteRemote:
			return "Delete Remote"
		case .deleteRemoteBranch:
			return "Delete Remote Branch"
		}
	}
}
