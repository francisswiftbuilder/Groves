import XCTest

@testable import Groves

final class GrovesAskPassLocatorTests: XCTestCase {
	func testTheLocatorResolvesTheHelperEmbeddedInTheHostBundle() throws {
		let expected = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass.app", directoryHint: .isDirectory)
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "MacOS", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass")

		XCTAssertTrue(
			FileManager.default.isExecutableFile(atPath: expected.path),
			"The app bundle must embed an executable AskPass helper"
		)
		XCTAssertEqual(GrovesAskPassLocator.bundledHelperURL, expected)
	}

	func testTheEmbeddedHelperCanExecuteWithoutAccessingCredentials() throws {
		let process = Process()
		process.executableURL = try XCTUnwrap(GrovesAskPassLocator.bundledHelperURL)
		process.arguments = ["credential", "get"]
		let input = Pipe()
		process.standardInput = input
		try input.fileHandleForWriting.write(contentsOf: Data("protocol=file\n\n".utf8))
		try input.fileHandleForWriting.close()
		try process.run()
		process.waitUntilExit()
		XCTAssertEqual(process.terminationReason, .exit)
		XCTAssertEqual(process.terminationStatus, 0)
	}
}
