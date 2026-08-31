import DomainGitInterface
import Foundation
import XCTest

@testable import Trees

final class RepositoryFileSystemMonitorTests: XCTestCase {
	func testEventsReturnsWhileStartupQueueIsSuspended() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let startupQueue = DispatchQueue(label: "dev.trees.repository-monitor-tests")
		startupQueue.suspend()
		let start = ContinuousClock.now
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: startupQueue
		)
		let elapsed = start.duration(to: .now)
		startupQueue.resume()

		XCTAssertLessThan(elapsed, .milliseconds(100))

		let eventTask = Task {
			for await _ in events {}
		}
		eventTask.cancel()
		await eventTask.value
		startupQueue.sync {}
	}

	func testEventsEmitsWhenNestedFileChanges() async throws {
		let directoryURL = FileManager.default.temporaryDirectory
			.appending(path: "TreesMonitorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
		let nestedDirectoryURL = directoryURL.appending(path: "Nested", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: nestedDirectoryURL,
			withIntermediateDirectories: true
		)
		defer {
			try? FileManager.default.removeItem(at: directoryURL)
		}

		let eventExpectation = expectation(description: "Receives a recursive file system event")
		let monitorQueue = DispatchQueue(label: "dev.trees.repository-monitor-event-tests")
		let events = RepositoryFileSystemMonitor.events(
			at: directoryURL,
			queue: monitorQueue
		)
		let eventTask = Task {
			var didFulfillExpectation = false
			for await paths in events {
				guard !didFulfillExpectation else { continue }
				let expectedDirectoryPath = directoryURL.standardizedFileURL.path
				XCTAssertTrue(
					paths.contains {
						URL(fileURLWithPath: $0).standardizedFileURL.path
							.hasPrefix(expectedDirectoryPath)
					}
				)
				didFulfillExpectation = true
				eventExpectation.fulfill()
			}
		}

		try Data("updated".utf8).write(to: nestedDirectoryURL.appending(path: "File.txt"))
		await fulfillment(of: [eventExpectation], timeout: 3)
		eventTask.cancel()
		await eventTask.value
		monitorQueue.sync {}
	}
}
