import XCTest

@testable import Trees

final class TreesAskPassLocatorTests: XCTestCase {
	func testTheLocatorResolvesTheHelperEmbeddedInTheHostBundle() throws {
		let expected = Bundle.main.bundleURL
			.appending(path: "Contents", directoryHint: .isDirectory)
			.appending(path: "Helpers", directoryHint: .isDirectory)
			.appending(path: "TreesAskPass")

		XCTAssertTrue(
			FileManager.default.isExecutableFile(atPath: expected.path),
			"The app bundle must embed an executable AskPass helper"
		)
		XCTAssertEqual(TreesAskPassLocator.bundledHelperURL, expected)
	}
}
