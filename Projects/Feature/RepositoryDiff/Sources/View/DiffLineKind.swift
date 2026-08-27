import DomainGitInterface
import SwiftUI

public enum DiffLineKind: Equatable, Sendable {
	case metadata
	case hunk
	case context
	case addition
	case deletion
}
