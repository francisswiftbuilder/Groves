enum RepositorySyncConfirmation {
	case forcePush(remoteName: String?)

	var title: String {
		"Force Push with Lease"
	}

	var message: String {
		switch self {
		case .forcePush(let remoteName):
			let destination = remoteName.map { " to \($0)" } ?? ""
			return
				"Remote history\(destination) may be rewritten. The push uses --force-with-lease to reject unexpected remote changes."
		}
	}

	var actionTitle: String {
		"Force Push with Lease"
	}
}
