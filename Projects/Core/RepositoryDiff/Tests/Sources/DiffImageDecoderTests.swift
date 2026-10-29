import AppKit
import Foundation
import Testing

@testable import CoreRepositoryDiff

struct DiffImageDecoderTests {
	@Test
	func testDecodeFallsBackToNSImageForSVG() async throws {
		let data = try #require(
			"""
			<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 24">
			  <rect width="48" height="24" fill="#000000"/>
			</svg>
			""".data(using: .utf8)
		)

		let image = await DiffImageDecoder.decode(data)

		#expect(image?.size == CGSize(width: 48, height: 24))
	}

	@Test
	func testDecodeReturnsNilForInvalidImageData() async {
		let image = await DiffImageDecoder.decode(Data("invalid".utf8))

		#expect(image == nil)
	}
}
