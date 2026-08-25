import DomainGitInterface
import Foundation

enum PendingRepositoryConfirmation {
	case discard([WorkingTreeChange])
	case discardHunk(GitDiffHunkSelection, WorkingTreeChange, GitDiffOptions)
	case markConflictResolved(GitConflict)
	case deleteBranch(GitBranch)
	case deleteTag(GitTag)
	case dropStash(GitStash)
	case forcePush(remoteName: String?)
	case operation(RepositoryOperationAction, RepositoryOperationKind)
	case hardReset(GitCommit)
	case deleteRemote(GitRemote)
	case deleteRemoteBranch(GitRemoteBranch)

	var title: String {
		switch self {
		case .discard(let changes):
			guard changes.count == 1, let change = changes.first else {
				return "Discard Changes to \(changes.count) Files?"
			}
			let fileName = URL(fileURLWithPath: change.path).lastPathComponent
			return "Discard Changes to “\(fileName)”"
		case .discardHunk(_, let change, _):
			let fileName = URL(fileURLWithPath: change.path).lastPathComponent
			return "Discard Hunk in “\(fileName)”"
		case .markConflictResolved:
			return "Mark Conflict as Resolved?"
		case .deleteBranch(let branch):
			return "Delete “\(branch.name)”"
		case .deleteTag(let tag):
			return "Delete “\(tag.name)”"
		case .dropStash:
			return "Delete Stash"
		case .forcePush:
			return "Force Push with Lease"
		case .operation(let action, let operation):
			return operationTitle(action: action, operation: operation)
		case .hardReset:
			return "Hard Reset"
		case .deleteRemote:
			return "Delete Remote"
		case .deleteRemoteBranch:
			return "Delete Remote Branch"
		}
	}

	var message: String {
		switch self {
		case .discard:
			return "Uncommitted changes in the selected files will be permanently discarded."
		case .discardHunk:
			return "The changes in this hunk will be permanently discarded from the working file."
		case .markConflictResolved:
			return
				"Conflict markers are still present in this file. Git will accept the file as resolved anyway."
		case .deleteBranch(let branch):
			return "The local branch “\(branch.name)” will be deleted. Remote branches are not affected."
		case .deleteTag(let tag):
			return "The local tag “\(tag.name)” will be deleted. Remote tags are not affected."
		case .dropStash(let stash):
			return "\(stash.reference) · \(stash.subject) will be permanently removed."
		case .forcePush(let remoteName):
			let destination = remoteName.map { " to \($0)" } ?? ""
			return
				"Remote history\(destination) may be rewritten. The push uses --force-with-lease to reject unexpected remote changes."
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
		case .deleteRemote(let remote):
			return
				"The local configuration for \(remote.name) will be removed. The remote repository is not deleted."
		case .deleteRemoteBranch(let branch):
			return "\(branch.fullName) will be deleted from \(branch.remoteName) for all collaborators."
		}
	}

	var actionTitle: String {
		switch self {
		case .discard: return "Discard Changes"
		case .discardHunk: return "Discard Hunk"
		case .markConflictResolved: return "Mark Resolved Anyway"
		case .deleteBranch: return "Delete Branch"
		case .deleteTag: return "Delete Tag"
		case .dropStash: return "Delete Stash"
		case .forcePush: return "Force Push with Lease"
		case .operation(let action, let operation):
			return operationTitle(action: action, operation: operation)
		case .hardReset: return "Hard Reset"
		case .deleteRemote: return "Delete Remote"
		case .deleteRemoteBranch: return "Delete Remote Branch"
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
