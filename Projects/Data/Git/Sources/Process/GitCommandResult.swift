import DomainGitInterface
import Foundation

struct GitCommandResult: Sendable {
	let standardOutputData: Data
	let standardOutput: String
	let standardError: String
}
