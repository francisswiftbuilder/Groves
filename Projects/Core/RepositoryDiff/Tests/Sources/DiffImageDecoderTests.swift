import AppKit
import XCTest

@testable import CoreRepositoryDiff

final class DiffImageDecoderTests: XCTestCase {
	func testDecodeFallsBackToNSImageForSVG() async throws {
		let data = try XCTUnwrap(
			"""
			<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24">
			  <rect width="48" height="24" fill="#000000"/>
			</svg>
			""".data(using: .utf8)
		)

		let image = await DiffImageDecoder.decode(data)

		XCTAssertEqual(image?.size, CGSize(width: 48, height: 24))
	}

	func testDecodeReturnsNilForInvalidImageData() async {
		let image = await DiffImageDecoder.decode(Data("invalid".utf8))

		XCTAssertNil(image)
	}
}
