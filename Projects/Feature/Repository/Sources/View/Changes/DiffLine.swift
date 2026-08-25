import DomainGitInterface
import SwiftUI

struct DiffLine: Identifiable, Equatable, Sendable {
	let number: Int
	let text: String
	let oldLineNumber: Int?
	let newLineNumber: Int?
	let kind: DiffLineKind
	var selection: GitDiffLineSelection?
	var hunkSelection: GitDiffHunkSelection?
	var changedRange: DiffTextRange?
	var showsAction = false

	var id: Int { number }

	var sourceText: String {
		guard isSourceLine else { return text }
		return String(text.dropFirst())
	}

	var isSourceLine: Bool {
		switch kind {
		case .context, .addition, .deletion:
			return true
		case .metadata, .hunk:
			return false
		}
	}
}
