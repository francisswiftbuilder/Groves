import Foundation

public protocol GitCredentialPersisting: Sendable {
	func commitPending(operationID: String) throws
	func discardPending(operationID: String) throws
}
