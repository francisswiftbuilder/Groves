import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

final class RepositoryFilePreviewTests: XCTestCase {
	func testMakeCreatesTextPreviewForUTF8Content() {
		let data = Data("let value = 1".utf8)

		let preview = RepositoryFilePreview.make(path: "Value.swift", data: data)

		XCTAssertEqual(
			preview,
			.text(content: "let value = 1", byteCount: data.count)
		)
	}

	func testMakeCreatesUnsupportedPreviewForBinaryContent() {
		let data = Data([0, 1, 2, 3])

		let preview = RepositoryFilePreview.make(path: "Archive.bin", data: data)

		XCTAssertEqual(preview, .unsupported(byteCount: data.count))
	}
}
