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
		XCTAssertEqual(items.map(\.visibleLaneCount), [1, 1])
	}

	func testBuildPreservesParentLanesForMergeCommit() {
		let merge = makeCommit(hash: "merge", parents: ["left", "right"])
		let left = makeCommit(hash: "left", parents: ["base"])
		let right = makeCommit(hash: "right", parents: ["base"])
		let base = makeCommit(hash: "base", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [merge, left, right, base])

		XCTAssertEqual(items[0].topLanes, ["merge"])
		XCTAssertEqual(items[0].bottomLanes, ["left", "right"])
		XCTAssertEqual(items[0].topLaneColorIndices, [0])
		XCTAssertEqual(items[0].bottomLaneColorIndices, [0, 1])
		XCTAssertEqual(items[1].topLanes, ["left", "right"])
		XCTAssertEqual(items[1].topLaneColorIndices, [0, 1])
		XCTAssertEqual(items[1].visibleLaneCount, 2)
		XCTAssertEqual(items[2].lane, 1)
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

	func testDiffParserPairsReplacementLinesWithSourceCoordinates() throws {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1,4 +1,4 @@
			 one
			-two
			+TWO
			 three
			"""

		let lines = DiffParser.parse(diff)
		let deletion = try XCTUnwrap(lines.first { $0.kind == .deletion })
		let addition = try XCTUnwrap(lines.first { $0.kind == .addition })

		XCTAssertEqual(deletion.oldLineNumber, 2)
		XCTAssertNil(deletion.newLineNumber)
		XCTAssertNil(addition.oldLineNumber)
		XCTAssertEqual(addition.newLineNumber, 2)
		XCTAssertEqual(
			deletion.selection,
			GitDiffLineSelection(oldLineNumber: 2, newLineNumber: 2)
		)
		XCTAssertEqual(addition.selection, deletion.selection)
		XCTAssertTrue(deletion.showsAction)
		XCTAssertFalse(addition.showsAction)
	}

	func testDiffParserTreatsTriplePrefixInsideHunkAsChangedContent() {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1 +1 @@
			---old
			+++new
			"""

		let lines = DiffParser.parse(diff)

		XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 1)
		XCTAssertEqual(lines.filter { $0.kind == .addition }.count, 1)
	}

	func testDiffParserReturnsOnlySourceLinesForPresentation() {
		let diff = """
			diff --git a/tracked.txt b/tracked.txt
			index 1111111..2222222 100644
			--- a/tracked.txt
			+++ b/tracked.txt
			@@ -1,2 +1,2 @@
			-old
			+new
			 context
			"""

		let lines = DiffParser.parseSourceLines(diff)

		XCTAssertEqual(lines.map(\.kind), [.deletion, .addition, .context])
		XCTAssertEqual(lines.map(\.sourceText), ["old", "new", "context"])
	}

	func testCommitDiffFileParserSeparatesChangedFiles() {
		let diff = """
			diff --git a/Sources/First.swift b/Sources/First.swift
			index 1111111..2222222 100644
			--- a/Sources/First.swift
			+++ b/Sources/First.swift
			@@ -1 +1 @@
			-old
			+new
			diff --git a/README.md b/README.md
			new file mode 100644
			--- /dev/null
			+++ b/README.md
			@@ -0,0 +1 @@
			+Read me
			"""

		let files = CommitDiffFileParser.parse(diff)

		XCTAssertEqual(files.map(\.path), ["Sources/First.swift", "README.md"])
		XCTAssertEqual(files.map(\.additions), [1, 1])
		XCTAssertEqual(files.map(\.deletions), [1, 0])
	}

	private func makeCommit(hash: String, parents: [String]) -> GitCommit {
		GitCommit(
			hash: hash,
			shortHash: hash,
			parentHashes: parents,
			author: "Author",
			date: Date(timeIntervalSince1970: 0),
			references: [],
			subject: hash,
			body: ""
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
