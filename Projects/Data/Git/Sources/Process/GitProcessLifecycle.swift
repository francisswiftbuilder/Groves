import Darwin
import Foundation

final class GitProcessLifecycle: @unchecked Sendable {
	private enum State {
		case notStarted
		case running
		case terminated
	}

	private let process: Process
	private let gracePeriod: TimeInterval
	private let lock = NSLock()
	private var state: State = .notStarted
	private var isCancelled = false
	private var processGroupIdentifier: pid_t?
	private var cancellationTask: Task<Void, Never>?

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
		guard state == .notStarted, !isCancelled else {
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
			let identifier = process.processIdentifier
			let groupIdentifier = getpgid(identifier)
			if groupIdentifier == identifier
				|| (groupIdentifier == -1 && errno == ESRCH && kill(-identifier, 0) == 0)
			{
				processGroupIdentifier = identifier
			}
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
		guard !isCancelled else {
			lock.unlock()
			return
		}
		isCancelled = true
		let hasRunningGroup = processGroupIdentifier.map { kill(-$0, 0) == 0 } ?? false
		guard state == .running || hasRunningGroup else {
			lock.unlock()
			return
		}
		if let processGroupIdentifier {
			kill(-processGroupIdentifier, SIGTERM)
		} else {
			process.terminate()
		}
		cancellationTask = Task {
			try? await Task.sleep(for: .seconds(gracePeriod))
			forceTermination()
		}
		lock.unlock()
	}

	func waitForCancellation() async {
		let task = lock.withLock { cancellationTask }
		await task?.value
	}

	private func forceTermination() {
		lock.lock()
		defer { lock.unlock() }
		if let processGroupIdentifier {
			kill(-processGroupIdentifier, SIGKILL)
		} else if state == .running {
			kill(process.processIdentifier, SIGKILL)
		}
	}

	private func markTerminated() {
		lock.lock()
		state = .terminated
		lock.unlock()
	}
}
