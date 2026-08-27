import DomainGitInterface

public enum ChangesDiffSelection: Equatable {
	case workingTree(WorkspaceChangeSelection, WorkingTreeChange, GitDiffSource)
	case amend(WorkspaceChangeSelection, GitAmendChange)

	var identifier: WorkspaceChangeSelection {
		switch self {
		case .workingTree(let selection, _, _), .amend(let selection, _):
			return selection
		}
	}

	var workingTreeChange: WorkingTreeChange? {
		guard case .workingTree(_, let change, _) = self else { return nil }
		return change
	}

	var source: GitDiffSource? {
		guard case .workingTree(_, _, let source) = self else { return nil }
		return source
	}
}
