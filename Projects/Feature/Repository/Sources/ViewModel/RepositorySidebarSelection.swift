import DomainGitInterface
import FeatureRepositoryInterface
import Foundation

enum RepositorySidebarSelection: Hashable {
	case section(repositoryID: RepositoryTab.ID, section: WorkspaceSection)
	case branch(repositoryID: RepositoryTab.ID, id: String)
	case remote(repositoryID: RepositoryTab.ID, id: String)
	case remoteBranch(repositoryID: RepositoryTab.ID, id: String)
	case tag(repositoryID: RepositoryTab.ID, id: String)
	case stash(repositoryID: RepositoryTab.ID, id: String)

	var repositoryID: RepositoryTab.ID {
		switch self {
		case .section(let repositoryID, _),
			.branch(let repositoryID, _),
			.remote(let repositoryID, _),
			.remoteBranch(let repositoryID, _),
			.tag(let repositoryID, _),
			.stash(let repositoryID, _):
			return repositoryID
		}
	}
}
