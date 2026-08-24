import DomainGitInterface
import Foundation
import UniformTypeIdentifiers

enum WorkspaceChangeSelection: Hashable {
	case workingTree(String)
	case amend(String)
}
