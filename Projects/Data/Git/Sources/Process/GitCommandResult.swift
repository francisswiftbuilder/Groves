import DomainGitInterface
import Foundation

struct GitCommandResult: Sendable {
	let terminationStatus: Int32
	let standardOutputData: Data
	let standardOutput: String
	let standardError: String
	let failureDescription: String?
}
