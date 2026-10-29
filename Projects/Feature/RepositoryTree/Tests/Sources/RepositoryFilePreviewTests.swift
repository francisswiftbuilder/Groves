import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryTree

struct RepositoryFilePreviewTests {
	@Test
	func testMakeCreatesTextPreviewForUTF8Content() {
		let data = Data("let value = 1".utf8)

		let preview = RepositoryFilePreview.make(path: "Value.swift", data: data)

		#expect(preview == .text(content: "let value = 1", byteCount: data.count))
	}

	@Test
	func testMakeCreatesUnsupportedPreviewForBinaryContent() {
		let data = Data([0, 1, 2, 3])

		let preview = RepositoryFilePreview.make(path: "Archive.bin", data: data)

		#expect(preview == .unsupported(byteCount: data.count))
	}
}
