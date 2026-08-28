import DomainGitInterface
import Foundation
import XCTest

@testable import Trees

final class RepositoryFileSystemMonitorTests: XCTestCase {
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
		let events = RepositoryFileSystemMonitor.events(at: directoryURL)
		let eventTask = Task {
			for await _ in events {
				eventExpectation.fulfill()
				return
			}
		}
		defer {
			eventTask.cancel()
		}

		try Data("updated".utf8).write(to: nestedDirectoryURL.appending(path: "File.txt"))
		await fulfillment(of: [eventExpectation], timeout: 3)
	}
}
