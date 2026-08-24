import DomainGitInterface
import Foundation

struct GitCommandResult: Sendable {
	let standardOutput: String
	let standardError: String
}
