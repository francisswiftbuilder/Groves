import DomainGitInterface
import Foundation
import Testing

@testable import Groves

struct RepositoryFileSystemMonitorTests {
	@Test
	func testEventsReturnsWhileStartupQueueIsSuspended() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let startupQueue = DispatchQueue(label: "dev.groves.repository-monitor-tests")
		startupQueue.suspend()
		let start = ContinuousClock.now
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: startupQueue
		)
		let elapsed = start.duration(to: .now)
		startupQueue.resume()

		#expect(elapsed < .milliseconds(100))

		let eventTask = Task {
			for await _ in events {}
		}
		eventTask.cancel()
		await eventTask.value
		startupQueue.sync {}
	}

	@Test
	func testEventsEmitsWhenNestedFileChanges() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "GrovesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		let nestedDirectoryURL = directoryURL.appending(path: "Nested", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: nestedDirectoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let monitorQueue = DispatchQueue(label: "dev.groves.repository-monitor-event-tests")
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: monitorQueue
		)
		try await confirmation("Receives a recursive file system event") { eventReceived in
			let eventTask = Task {
				for await paths in events {
					let expectedDirectoryPath = directoryURL.standardizedFileURL.path
					#expect(
						paths.contains {
							URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(expectedDirectoryPath)
						})
					eventReceived()
					return
				}
			}
			let timeoutTask = Task {
				try await Task.sleep(for: .seconds(3))
				eventTask.cancel()
			}
			defer {
				eventTask.cancel()
				timeoutTask.cancel()
			}
			monitorQueue.sync {}
			try Data("updated".utf8).write(to: nestedDirectoryURL.appending(path: "File.txt"))
			await eventTask.value
		}
		monitorQueue.sync {}
	}
}
