import Foundation

public enum GitPushTarget: Hashable, Sendable {
	case upstream
	case setUpstream(remoteName: String, branchName: String)
}
