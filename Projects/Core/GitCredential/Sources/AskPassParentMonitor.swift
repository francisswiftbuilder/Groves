import Darwin
import Foundation

@MainActor
public final class AskPassParentMonitor: AskPassParentMonitoring {
	private let pollInterval: TimeInterval
	private var monitoringTask: Task<Void, Never>?

	public init(pollInterval: TimeInterval = 0.25) {
		self.pollInterval = pollInterval
	}

	deinit {
		monitoringTask?.cancel()
	}

	public func startMonitoring(
		parentProcessIdentifier: Int32,
		onParentExit: @escaping () -> Void
	) {
		stopMonitoring()
		let interval = pollInterval
		monitoringTask = Task { [weak self] in
			while !Task.isCancelled {
				do {
					try await Task.sleep(for: .seconds(interval))
				} catch {
					return
				}
				guard let self, !Task.isCancelled else { return }
				guard !Self.processExists(parentProcessIdentifier) else { continue }
				stopMonitoring()
				onParentExit()
				return
			}
		}
	}

	public func stopMonitoring() {
		monitoringTask?.cancel()
		monitoringTask = nil
	}

	private static func processExists(_ processIdentifier: Int32) -> Bool {
		kill(processIdentifier, 0) == 0 || errno == EPERM
	}
}
