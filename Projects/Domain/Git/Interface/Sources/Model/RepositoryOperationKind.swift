public enum RepositoryOperationKind: String, Hashable, Sendable {
	case merge
	case rebase
	case cherryPick
	case revert
}
