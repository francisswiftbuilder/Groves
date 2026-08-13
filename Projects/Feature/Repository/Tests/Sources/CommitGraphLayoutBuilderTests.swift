import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepository

final class CommitGraphLayoutBuilderTests: XCTestCase {
	func testBuildPlacesLinearHistoryInSingleLane() {
		let child = makeCommit(hash: "child", parents: ["parent"])
		let parent = makeCommit(hash: "parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [child, parent])

		XCTAssertEqual(items.map(\.lane), [0, 0])
		XCTAssertEqual(items.first?.bottomLanes, ["parent"])
	}

	func testRepositoryTreeLayoutIncludesChildrenOfExpandedDirectories() {
		let source = RepositoryTreeNode(
			name: "Sources",
			path: "Sources",
			children: [
				RepositoryTreeNode(
					name: "App.swift",
					path: "Sources/App.swift",
					children: []
				)
			]
		)
		let readme = RepositoryTreeNode(name: "README.md", path: "README.md", children: [])

		let items = RepositoryTreeLayoutBuilder.build(
			nodes: [source, readme],
			expandedNodeIDs: [source.id]
		)

		XCTAssertEqual(items.map(\.node.name), ["Sources", "App.swift", "README.md"])
		XCTAssertEqual(items.map(\.depth), [0, 1, 0])
		XCTAssertEqual(items[1].ancestorHasFollowingSibling, [true])
	}

	private func makeCommit(hash: String, parents: [String]) -> GitCommit {
		GitCommit(
			hash: hash,
			shortHash: hash,
			parentHashes: parents,
			author: "Author",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: hash
		)
	}
}

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
