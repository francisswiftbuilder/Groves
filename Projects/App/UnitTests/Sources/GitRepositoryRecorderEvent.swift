import DomainGitInterface
import Foundation

enum GitRepositoryRecorderEvent: Equatable, Sendable {
	case repositoryRoot(URL)
	case clone(remoteURL: String, directoryURL: URL)
	case loadDiff(GitDiffSource)
	case applyDiffLine(GitDiffLineAction)
	case stage(path: String)
	case merge(branchName: String)
	case createBranch(name: String, commitHash: String?)
	case checkoutCommit(String)
	case createTag(name: String, message: String, commitHash: String)
	case deleteTag(name: String)
	case push(GitPushTarget)
	case forcePush(GitPushTarget)
	case pushTags(remoteName: String)
}
