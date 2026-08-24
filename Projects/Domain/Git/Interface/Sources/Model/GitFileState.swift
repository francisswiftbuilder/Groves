import Foundation

public enum GitFileState: String, Sendable {
	case added
	case copied
	case deleted
	case ignored
	case modified
	case renamed
	case typeChanged
	case unmerged
	case untracked
	case unchanged

}
