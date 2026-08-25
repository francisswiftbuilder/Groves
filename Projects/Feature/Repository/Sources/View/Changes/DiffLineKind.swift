import DomainGitInterface
import SwiftUI

enum DiffLineKind: Equatable, Sendable {
	case metadata
	case hunk
	case context
	case addition
	case deletion
}
