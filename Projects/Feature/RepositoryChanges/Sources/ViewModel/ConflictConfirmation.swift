import DomainGitInterface

enum ConflictConfirmation {
	case markResolved(GitConflict)

	var title: String {
		"Mark Conflict as Resolved?"
	}

	var message: String {
		"Conflict markers are still present in this file. Git will accept the file as resolved anyway."
	}

	var actionTitle: String {
		"Mark Resolved Anyway"
	}
}
