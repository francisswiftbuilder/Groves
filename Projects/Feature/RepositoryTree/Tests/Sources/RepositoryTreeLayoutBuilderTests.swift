import DomainGitInterface
import XCTest

@testable import FeatureRepositoryTree

final class RepositoryTreeLayoutBuilderTests: XCTestCase {
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
}
