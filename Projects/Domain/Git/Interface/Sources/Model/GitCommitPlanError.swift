import Foundation

public enum GitCommitPlanError: LocalizedError {
	case noStagedChanges
	case repositoryChanged
	case invalidPlan
	case modelUnavailable(String)
	case contextTooLarge

	public var errorDescription: String? {
		switch self {
		case .noStagedChanges:
			"Stage the changes you want to organize, then try again."
		case .repositoryChanged:
			"The branch or staged changes have changed. Organize the current changes again before committing."
		case .invalidPlan:
			"The suggested commits couldn’t be verified. Try organizing your changes again."
		case .modelUnavailable(let reason):
			reason
		case .contextTooLarge:
			"These changes are too large for the available model. Stage a smaller set of changes and try again."
		}
	}
}
