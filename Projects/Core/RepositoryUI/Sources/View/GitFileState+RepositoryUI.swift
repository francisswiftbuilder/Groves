import DomainGitInterface

extension GitFileState {
	public var title: String {
		switch self {
		case .added: return "Added"
		case .copied: return "Copied"
		case .deleted: return "Deleted"
		case .ignored: return "Ignored"
		case .modified: return "Modified"
		case .renamed: return "Renamed"
		case .typeChanged: return "Type Changed"
		case .unmerged: return "Unmerged"
		case .untracked: return "Untracked"
		case .unchanged: return "Unchanged"
		}
	}

	public var symbol: String {
		switch self {
		case .added: return "A"
		case .copied: return "C"
		case .deleted: return "D"
		case .ignored: return "!"
		case .modified: return "M"
		case .renamed: return "R"
		case .typeChanged: return "T"
		case .unmerged: return "U"
		case .untracked: return "?"
		case .unchanged: return " "
		}
	}
}
