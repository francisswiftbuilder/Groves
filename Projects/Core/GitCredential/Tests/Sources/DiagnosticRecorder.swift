import Foundation

@testable import CoreGitCredential

final class DiagnosticRecorder: @unchecked Sendable {
	private let lock = NSLock()
	private var diagnostics: [String] = []

	var values: [String] {
		lock.withLock { diagnostics }
	}

	func record(_ error: GitCredentialStoreError) {
		lock.withLock {
			diagnostics.append(error.diagnosticDescription)
		}
	}
}
