public enum GitBranchDeletionOutcome: Sendable {
	case deleted
	case deletedWithWarning(String)
}
