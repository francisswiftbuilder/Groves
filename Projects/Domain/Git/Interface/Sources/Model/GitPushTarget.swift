import Foundation

public enum GitPushTarget: Hashable, Sendable {
	case upstream(branchName: String? = nil, remoteName: String? = nil)
	case setUpstream(remoteName: String, branchName: String)
}
