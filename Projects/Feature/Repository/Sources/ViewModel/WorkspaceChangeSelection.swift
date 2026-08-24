import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

enum WorkspaceChangeSelection: Hashable {
	case staged(String)
	case unstaged(String)
	case amend(String)

	var changeID: String {
		switch self {
		case .staged(let id), .unstaged(let id), .amend(let id):
			return id
		}
	}

	var isStaged: Bool {
		if case .staged = self {
			return true
		}
		return false
	}
}
