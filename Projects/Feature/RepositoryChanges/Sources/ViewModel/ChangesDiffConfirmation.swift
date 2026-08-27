import DomainGitInterface
import Foundation

public struct ChangesDiffConfirmation {
	let selection: GitDiffHunkSelection
	let change: WorkingTreeChange
	let options: GitDiffOptions

	var title: String {
		let fileName = URL(fileURLWithPath: change.path).lastPathComponent
		return "Discard Hunk in \(fileName)"
	}

	var message: String {
		"The changes in this hunk will be permanently discarded from the working file."
	}

	var actionTitle: String {
		"Discard Hunk"
	}
}
