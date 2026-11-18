import DomainGitInterface
import Foundation

public enum ChangesConfirmation {
	case discard(GitDiscardContext, repositoryURL: URL)

	public var title: String {
		let changes = changes
		guard changes.count == 1, let change = changes.first else {
			return "Discard Changes to \(changes.count) Files?"
		}
		let fileName = URL(fileURLWithPath: change.path).lastPathComponent
		return "Discard Changes to “\(fileName)”"
	}

	public var message: String {
		"Existing versions of the selected files will be moved to the Trash. Staged changes will be kept."
	}

	public var actionTitle: String {
		"Discard Changes"
	}

	var changes: [WorkingTreeChange] {
		switch self {
		case .discard(let context, _):
			return context.changes
		}
	}
}
