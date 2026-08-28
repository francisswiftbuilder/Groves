import Darwin
import Foundation

@MainActor
final class AskPassParentMonitor: AskPassParentMonitoring {
	private let pollInterval: TimeInterval
	private var timer: DispatchSourceTimer?

	init(pollInterval: TimeInterval = 0.25) {
		self.pollInterval = pollInterval
	}

	func startMonitoring(parentProcessIdentifier: Int32, onParentExit: @escaping () -> Void) {
		stopMonitoring()
		let timer = DispatchSource.makeTimerSource(queue: .main)
		timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
		timer.setEventHandler {
			guard kill(parentProcessIdentifier, 0) != 0 else { return }
			onParentExit()
		}
		timer.resume()
		self.timer = timer
	}

	func stopMonitoring() {
		timer?.cancel()
		timer = nil
	}
}
