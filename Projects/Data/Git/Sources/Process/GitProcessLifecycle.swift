import Darwin
import Foundation

final class GitProcessLifecycle: @unchecked Sendable {
	private enum State {
		case notStarted
		case running
		case cancelled
		case terminated
	}

	private let process: Process
	private let gracePeriod: TimeInterval
	private let lock = NSLock()
	private var state: State = .notStarted

	init(process: Process, gracePeriod: TimeInterval) {
		self.process = process
		self.gracePeriod = gracePeriod
	}

	@discardableResult
	func start(
		onTermination: @escaping @Sendable (Int32) -> Void,
		onFailure: @escaping @Sendable (any Error) -> Void
	) -> Bool {
		lock.lock()
		guard state == .notStarted else {
			lock.unlock()
			onFailure(CancellationError())
			return false
		}
		process.terminationHandler = { [weak self] process in
			self?.markTerminated()
			onTermination(process.terminationStatus)
		}
		do {
			try process.run()
			state = .running
			lock.unlock()
			return true
		} catch {
			state = .terminated
			lock.unlock()
			onFailure(error)
			return false
		}
	}

	func cancel() {
		lock.lock()
		let wasRunning = state == .running
		if state != .terminated {
			state = .cancelled
		}
		let processIdentifier = wasRunning ? process.processIdentifier : nil
		lock.unlock()

		guard wasRunning, let processIdentifier else { return }
		process.terminate()
		DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + gracePeriod) {
			guard self.isRunning else { return }
			kill(processIdentifier, SIGKILL)
		}
	}

	private var isRunning: Bool {
		lock.lock()
		defer { lock.unlock() }
		return state == .running || state == .cancelled
	}

	private func markTerminated() {
		lock.lock()
		state = .terminated
		lock.unlock()
	}
}
