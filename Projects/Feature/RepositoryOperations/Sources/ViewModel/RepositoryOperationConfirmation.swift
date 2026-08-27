import DomainGitInterface

enum RepositoryOperationConfirmation {
	case operation(RepositoryOperationAction, RepositoryOperationKind)
	case hardReset(GitCommit)

	var title: String {
		switch self {
		case .operation(let action, let operation):
			return operationTitle(action: action, operation: operation)
		case .hardReset: return "Hard Reset"
		}
	}

	var message: String {
		switch self {
		case .operation(let action, let operation):
			switch action {
			case .abort:
				return
					"The in-progress \(operationDisplayName(operation).lowercased()) and its current resolution work will be discarded."
			case .skip:
				return
					"The current commit will be omitted from the in-progress \(operationDisplayName(operation).lowercased())."
			case .continue:
				return "The \(operationDisplayName(operation).lowercased()) will continue."
			}
		case .hardReset(let commit):
			return
				"Tracked changes after \(commit.shortHash) will be discarded. Untracked files are preserved."
		}
	}

	var actionTitle: String {
		switch self {
		case .operation(let action, let operation):
			return operationTitle(action: action, operation: operation)
		case .hardReset: return "Hard Reset"
		}
	}

	private func operationTitle(
		action: RepositoryOperationAction,
		operation: RepositoryOperationKind
	) -> String {
		switch action {
		case .continue: return "Continue \(operationDisplayName(operation))"
		case .skip: return "Skip Commit"
		case .abort: return "Abort \(operationDisplayName(operation))"
		}
	}

	private func operationDisplayName(_ operation: RepositoryOperationKind) -> String {
		switch operation {
		case .merge: return "Merge"
		case .rebase: return "Rebase"
		case .cherryPick: return "Cherry-pick"
		case .revert: return "Revert"
		}
	}
}
