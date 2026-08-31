import Foundation
import Security

protocol GitCredentialSecurityClient: Sendable {
	func add(_ attributes: [String: Any]) -> OSStatus
	func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
	func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?)
	func delete(_ query: [String: Any]) -> OSStatus
}
