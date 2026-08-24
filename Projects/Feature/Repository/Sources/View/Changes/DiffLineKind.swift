import DomainGitInterface
import SwiftUI

enum DiffLineKind: Equatable {
	case metadata
	case hunk
	case context
	case addition
	case deletion
}
