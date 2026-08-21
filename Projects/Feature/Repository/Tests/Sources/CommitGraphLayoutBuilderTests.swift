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
		XCTAssertEqual(items.first?.bottomColumns.map(\.targetHash), ["parent"])
		XCTAssertEqual(items.map(\.visibleLaneCount), [1, 1])
		XCTAssertEqual(items[0].topColumns[0].id, items[0].bottomColumns[0].id)
		XCTAssertEqual(items[0].nodeColorIndex, items[1].nodeColorIndex)
	}

	func testBuildPreservesParentLanesForMergeCommit() {
		let merge = makeCommit(hash: "merge", parents: ["left", "right"])
		let left = makeCommit(hash: "left", parents: ["base"])
		let right = makeCommit(hash: "right", parents: ["base"])
		let base = makeCommit(hash: "base", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [merge, left, right, base])

		XCTAssertEqual(items[0].topColumns.map(\.targetHash), ["merge"])
		XCTAssertEqual(items[0].bottomColumns.map(\.targetHash), ["left", "right"])
		XCTAssertEqual(items[0].topColumns.map(\.colorIndex), [0])
		XCTAssertEqual(items[0].bottomColumns.map(\.colorIndex), [0, 1])
		XCTAssertEqual(items[1].topColumns.map(\.targetHash), ["left", "right"])
		XCTAssertEqual(items[1].topColumns.map(\.colorIndex), [0, 1])
		XCTAssertEqual(items[1].visibleLaneCount, 2)
		XCTAssertEqual(items[2].lane, 1)
		for index in items.indices.dropLast() {
			XCTAssertEqual(items[index].bottomColumns, items[index + 1].topColumns)
		}
	}

	func testBuildKeepsExistingColumnColorWhenParentAlreadyHasLane() {
		let firstChild = makeCommit(hash: "first-child", parents: ["parent"])
		let secondChild = makeCommit(hash: "second-child", parents: ["parent"])
		let parent = makeCommit(hash: "parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(
			commits: [firstChild, secondChild, parent]
		)

		let secondChildItem = items[1]
		let currentColor = secondChildItem.nodeColorIndex
		let parentColumn = secondChildItem.bottomColumns.first { $0.targetHash == parent.id }
		let parentSegment = secondChildItem.outgoingSegments.first {
			$0.columnID == parentColumn?.id
		}

		XCTAssertNotEqual(parentColumn?.colorIndex, currentColor)
		XCTAssertEqual(parentSegment?.colorIndex, parentColumn?.colorIndex)
		XCTAssertEqual(items[2].nodeColorIndex, parentColumn?.colorIndex)
	}

	func testBuildMaintainsSegmentColorAcrossRowBoundaries() {
		let merge = makeCommit(hash: "merge", parents: ["left", "right"])
		let left = makeCommit(hash: "left", parents: ["base"])
		let right = makeCommit(hash: "right", parents: ["base"])
		let base = makeCommit(hash: "base", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [merge, left, right, base])

		for index in items.indices.dropLast() {
			for column in items[index].bottomColumns {
				let outgoingSegments = items[index].outgoingSegments.filter {
					$0.columnID == column.id
				}
				let incomingSegments = items[index + 1].incomingSegments.filter {
					$0.columnID == column.id
				}

				XCTAssertFalse(outgoingSegments.isEmpty)
				XCTAssertTrue(outgoingSegments.allSatisfy { $0.colorIndex == column.colorIndex })
				XCTAssertEqual(incomingSegments.map(\.colorIndex), [column.colorIndex])
			}
		}
	}

	func testBuildStartsUnrelatedHistoryWithoutReplacingAnExistingLane() throws {
		let firstHead = makeCommit(hash: "first-head", parents: ["first-parent"])
		let secondHead = makeCommit(hash: "second-head", parents: ["second-parent"])
		let firstParent = makeCommit(hash: "first-parent", parents: [])
		let secondParent = makeCommit(hash: "second-parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(
			commits: [firstHead, secondHead, firstParent, secondParent]
		)

		let firstBottomColumn = try XCTUnwrap(items[0].bottomColumns.first)
		let secondItem = items[1]

		XCTAssertEqual(secondItem.lane, 1)
		XCTAssertEqual(secondItem.topColumns[0], firstBottomColumn)
		XCTAssertEqual(
			secondItem.incomingSegments.map(\.columnID),
			[firstBottomColumn.id]
		)
		XCTAssertFalse(
			secondItem.incomingSegments.contains {
				$0.columnID == secondItem.topColumns[secondItem.lane].id
			}
		)
	}

	func testBuildDoesNotDrawIncomingLineAboveFirstVisibleCommit() {
		let head = makeCommit(hash: "head", parents: ["parent"])
		let parent = makeCommit(hash: "parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [head, parent])

		XCTAssertTrue(items[0].incomingSegments.isEmpty)
		XCTAssertEqual(items[0].outgoingSegments.map(\.colorIndex), [0])
		XCTAssertEqual(items[1].incomingSegments.map(\.colorIndex), [0])
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
