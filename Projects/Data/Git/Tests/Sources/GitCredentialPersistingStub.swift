import CoreGitCredential
import Foundation

final class GitCredentialPersistingStub: GitCredentialPersisting, @unchecked Sendable {
	private let lock = NSLock()
	private let commitError: (any Error)?
	private let discardError: (any Error)?
	private var recordedCommitCount = 0
	private var recordedDiscardCount = 0

	init(commitError: (any Error)? = nil, discardError: (any Error)? = nil) {
		self.commitError = commitError
		self.discardError = discardError
	}

	var commitCount: Int {
		lock.withLock { recordedCommitCount }
	}

	var discardCount: Int {
		lock.withLock { recordedDiscardCount }
	}

	func commitPending(operationID: String) throws {
		lock.withLock { recordedCommitCount += 1 }
		if let commitError { throw commitError }
	}

	func discardPending(operationID: String) throws {
		lock.withLock { recordedDiscardCount += 1 }
		if let discardError { throw discardError }
	}
}
