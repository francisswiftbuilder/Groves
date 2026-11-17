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
				"Remote history\(destination) may be rewritten. Only commits previously included in this local branch can be replaced, and further remote changes will be rejected."
		}
	}

	var actionTitle: String {
		"Force Push with Lease"
	}
}
