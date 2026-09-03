import XCTest

@testable import Groves

final class GrovesAskPassLocatorTests: XCTestCase {
	func testTheLocatorResolvesTheHelperEmbeddedInTheHostBundle() throws {
		let expected = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "GrovesAskPass")

		XCTAssertTrue(
			FileManager.default.isExecutableFile(atPath: expected.path),
			"The app bundle must embed an executable AskPass helper"
		)
		XCTAssertEqual(GrovesAskPassLocator.bundledHelperURL, expected)
	}
}
