public enum GitBranchCreationSource: Sendable {
	case head
	case commit(String)
	case remoteBranch(GitRemoteBranch)
}
