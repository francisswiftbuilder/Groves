import DomainGitInterface
import Foundation

public enum ChangesConfirmation {
	case discard([WorkingTreeChange])

	public var title: String {
		let changes = changes
		guard changes.count == 1, let change = changes.first else {
			return "Discard Changes to \(changes.count) Files?"
		}
		let fileName = URL(fileURLWithPath: change.path).lastPathComponent
		return "Discard Changes to “\(fileName)”"
	}

	public var message: String {
		"Uncommitted changes in the selected files will be permanently discarded."
	}

	public var actionTitle: String {
		"Discard Changes"
	}

	var changes: [WorkingTreeChange] {
		switch self {
		case .discard(let changes):
			return changes
		}
	}
}
