import DomainGitInterface
import Foundation

struct RepositoryResetPresentation: Identifiable {
	let id = UUID()
	let commit: GitCommit
	let repositoryURL: URL
	let context: GitResetContext
}
