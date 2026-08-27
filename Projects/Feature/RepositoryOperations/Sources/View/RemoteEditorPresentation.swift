import DomainGitInterface

enum RemoteEditorPresentation: Identifiable {
	case add
	case edit(GitRemote)

	var id: String {
		switch self {
		case .add: return "add"
		case .edit(let remote): return "edit-\(remote.id)"
		}
	}
}
