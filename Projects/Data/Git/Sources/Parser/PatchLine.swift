import DomainGitInterface
import Foundation

struct PatchLine {
	let text: String
	let oldLineNumber: Int
	let newLineNumber: Int
	let hasNoNewlineMarker: Bool
}
