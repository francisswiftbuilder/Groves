import DomainGitInterface
import Foundation

struct RepositoryWindowRestoration: Equatable {
	let primaryRepositoryID: RepositoryTab.ID?
	let additionalRepositoryIDs: [RepositoryTab.ID]
}
