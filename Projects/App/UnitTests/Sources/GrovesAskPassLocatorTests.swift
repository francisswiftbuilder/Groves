import Foundation
import Testing

@testable import Groves

struct GrovesAskPassLocatorTests {
	@Test
	func testTheLocatorResolvesTheHelperEmbeddedInTheHostBundle() throws {
		let expected = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass.app", directoryHint: .isDirectory)
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "MacOS", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass")

		#expect(
			FileManager.default.isExecutableFile(atPath: expected.path),
			"The app bundle must embed an executable AskPass helper")
		#expect(GrovesAskPassLocator.bundledHelperURL == expected)
	}

	@Test
	func testTheEmbeddedHelperCanExecuteWithoutAccessingCredentials() throws {
		let process = Process()
		process.executableURL = try #require(GrovesAskPassLocator.bundledHelperURL)
		process.arguments = ["credential", "get"]
		let input = Pipe()
		process.standardInput = input
		try input.fileHandleForWriting.write(contentsOf: Data("protocol=file\n\n".utf8))
		try input.fileHandleForWriting.close()
		try process.run()
		process.waitUntilExit()
		#expect(process.terminationReason == .exit)
		#expect(process.terminationStatus == 0)
	}
}
