import Foundation
import Testing

@testable import CoreGitCredential

@MainActor
struct AskPassParentMonitorTests {
	@Test
	func parentExitIsReportedOnce() async throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sleep")
		process.arguments = ["0.01"]
		try process.run()
		let monitor = AskPassParentMonitor(pollInterval: 0.01)

		await confirmation(expectedCount: 1) { confirmation in
			monitor.startMonitoring(parentProcessIdentifier: process.processIdentifier) {
				confirmation()
			}
			try? await Task.sleep(for: .milliseconds(500))
		}

		monitor.stopMonitoring()
	}
}
