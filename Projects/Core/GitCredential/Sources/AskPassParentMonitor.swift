import Darwin
import Foundation

@MainActor
public final class AskPassParentMonitor: AskPassParentMonitoring {
	private let pollInterval: TimeInterval
	private var timer: DispatchSourceTimer?

	public init(pollInterval: TimeInterval = 0.25) {
		self.pollInterval = pollInterval
	}

	public func startMonitoring(
		parentProcessIdentifier: Int32,
		onParentExit: @escaping () -> Void
	) {
		stopMonitoring()
		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
		timer.setEventHandler { [weak self] in
			guard Self.processExists(parentProcessIdentifier) == false else { return }
			self?.stopMonitoring()
			onParentExit()
		}
		timer.resume()
		self.timer = timer
	}

	public func stopMonitoring() {
		timer?.cancel()
		timer = nil
	}

	private static func processExists(_ processIdentifier: Int32) -> Bool {
		kill(processIdentifier, 0) == 0 || errno == EPERM
	}
}
