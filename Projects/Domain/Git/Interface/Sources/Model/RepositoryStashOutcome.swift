public enum RepositoryStashOutcome: Hashable, Sendable {
	case completed
	case nothingToSave
	case conflicted
	case failed(String)
}
