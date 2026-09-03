public enum RepositoryPushAction: Equatable, Sendable {
	case unavailable
	case upstream
	case setUpstream(remoteName: String, branchName: String)
	case chooseRemote(remoteNames: [String], branchName: String)
}
