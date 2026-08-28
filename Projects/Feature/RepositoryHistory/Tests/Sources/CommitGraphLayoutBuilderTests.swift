import DomainGitInterface
import Foundation
import XCTest

@testable import FeatureRepositoryHistory

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
