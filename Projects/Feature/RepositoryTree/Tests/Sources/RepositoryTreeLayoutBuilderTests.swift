import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryTree

struct RepositoryTreeLayoutBuilderTests {
	@Test
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

		#expect(items.map(\.node.name) == ["Sources", "App.swift", "README.md"])
		#expect(items.map(\.depth) == [0, 1, 0])
		#expect(items[1].ancestorHasFollowingSibling == [true])
	}
}
