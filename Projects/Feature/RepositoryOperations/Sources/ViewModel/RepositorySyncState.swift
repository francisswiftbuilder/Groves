import DomainGitInterface

struct RepositorySyncState: Equatable {
	let remotes: [GitRemote]
	let pushAction: RepositoryPushAction

	static let empty = RepositorySyncState(
		remotes: [],
		pushAction: .unavailable
	)
}
