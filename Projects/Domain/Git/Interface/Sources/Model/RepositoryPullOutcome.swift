import Foundation

public enum RepositoryPullOutcome: Hashable, Sendable {
	case upToDate
	case aheadOnly(aheadCount: Int)
	case fastForwarded
	case diverged(RepositoryPullDivergence)
}
