import DomainGitInterface
import SwiftUI

struct RepositorySidebarGroup: Hashable {
	let repositoryID: RepositoryTab.ID
	let kind: RepositorySidebarGroupKind
}
