import DomainGitInterface
import Foundation
import Testing

actor OperationsMutationGate {
	private(set) var requestCount = 0
	private var pending: [Int: CheckedContinuation<RepositorySnapshot, Error>] = [:]

	func load() async throws -> RepositorySnapshot {
		let index = requestCount
		requestCount += 1
		return try await withCheckedThrowingContinuation { pending[index] = $0 }
	}

	func resume(_ index: Int, with result: Result<RepositorySnapshot, Error>) {
		pending.removeValue(forKey: index)?.resume(with: result)
	}

	func waitForRequests(_ count: Int) async throws {
		let clock = ContinuousClock()
		let deadline = clock.now.advanced(by: .seconds(5))
		while requestCount < count {
			guard clock.now < deadline else {
				Issue.record("Timed out waiting for the requested operation")
				throw CancellationError()
			}
			try await Task.sleep(for: .milliseconds(5))
		}
	}
}
