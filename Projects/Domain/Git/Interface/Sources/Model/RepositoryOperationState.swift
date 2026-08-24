import Foundation

public enum RepositoryOperationState: Hashable, Sendable {
	case normal
	case detachedHead
	case mergeInProgress
	case rebaseInProgress
	case cherryPickInProgress
	case revertInProgress
	case conflicted
}
