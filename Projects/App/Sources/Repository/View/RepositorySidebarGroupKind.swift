import DomainGitInterface
import SwiftUI

enum RepositorySidebarGroupKind: CaseIterable, Hashable {
	case branches
	case remotes
	case tags
	case stashes

	init?(section: WorkspaceSection) {
		switch section {
		case .branches:
			self = .branches
		case .remotes:
			self = .remotes
		case .stashes:
			self = .stashes
		case .changes, .history, .tree:
			return nil
		}
	}
}
