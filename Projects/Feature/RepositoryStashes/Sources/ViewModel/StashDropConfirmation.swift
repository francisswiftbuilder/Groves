import DomainGitInterface
import Foundation

struct StashDropConfirmation: Equatable {
	let stash: GitStash
	let repositoryURL: URL
}
