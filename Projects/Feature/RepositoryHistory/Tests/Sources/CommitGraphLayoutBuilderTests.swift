import DomainGitInterface
import Foundation
import Testing

@testable import FeatureRepositoryHistory

struct CommitGraphLayoutBuilderTests {
	@Test
	func testBuildPlacesLinearHistoryInSingleLane() {
		let child = makeCommit(hash: "child", parents: ["parent"])
		let parent = makeCommit(hash: "parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [child, parent])

		#expect(items.map(\.lane) == [0, 0])
		#expect(items.first?.bottomColumns.map(\.targetHash) == ["parent"])
		#expect(items.map(\.visibleLaneCount) == [1, 1])
		#expect(items[0].topColumns[0].id == items[0].bottomColumns[0].id)
		#expect(items[0].nodeColorIndex == items[1].nodeColorIndex)
	}

	@Test
	func testBuildPreservesParentLanesForMergeCommit() {
		let merge = makeCommit(hash: "merge", parents: ["left", "right"])
		let left = makeCommit(hash: "left", parents: ["base"])
		let right = makeCommit(hash: "right", parents: ["base"])
		let base = makeCommit(hash: "base", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [merge, left, right, base])

		#expect(items[0].topColumns.map(\.targetHash) == ["merge"])
		#expect(items[0].bottomColumns.map(\.targetHash) == ["left", "right"])
		#expect(items[0].topColumns.map(\.colorIndex) == [0])
		#expect(items[0].bottomColumns.map(\.colorIndex) == [0, 1])
		#expect(items[1].topColumns.map(\.targetHash) == ["left", "right"])
		#expect(items[1].topColumns.map(\.colorIndex) == [0, 1])
		#expect(items[1].visibleLaneCount == 2)
		#expect(items[2].lane == 1)
		for index in items.indices.dropLast() {
			#expect(items[index].bottomColumns == items[index + 1].topColumns)
		}
	}

	@Test
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

		#expect(parentColumn?.colorIndex != currentColor)
		#expect(parentSegment?.colorIndex == parentColumn?.colorIndex)
		#expect(items[2].nodeColorIndex == parentColumn?.colorIndex)
	}

	@Test
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

				#expect(!(outgoingSegments.isEmpty))
				#expect(outgoingSegments.allSatisfy { $0.colorIndex == column.colorIndex })
				#expect(incomingSegments.map(\.colorIndex) == [column.colorIndex])
			}
		}
	}

	@Test
	func testBuildStartsUnrelatedHistoryWithoutReplacingAnExistingLane() throws {
		let firstHead = makeCommit(hash: "first-head", parents: ["first-parent"])
		let secondHead = makeCommit(hash: "second-head", parents: ["second-parent"])
		let firstParent = makeCommit(hash: "first-parent", parents: [])
		let secondParent = makeCommit(hash: "second-parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(
			commits: [firstHead, secondHead, firstParent, secondParent]
		)

		let firstBottomColumn = try #require(items[0].bottomColumns.first)
		let secondItem = items[1]

		#expect(secondItem.lane == 1)
		#expect(secondItem.topColumns[0] == firstBottomColumn)
		#expect(secondItem.incomingSegments.map(\.columnID) == [firstBottomColumn.id])
		#expect(
			!(secondItem.incomingSegments.contains {
				$0.columnID == secondItem.topColumns[secondItem.lane].id
			}))
	}

	@Test
	func testBuildDoesNotDrawIncomingLineAboveFirstVisibleCommit() {
		let head = makeCommit(hash: "head", parents: ["parent"])
		let parent = makeCommit(hash: "parent", parents: [])

		let items = CommitGraphLayoutBuilder.build(commits: [head, parent])

		#expect(items[0].incomingSegments.isEmpty)
		#expect(items[0].outgoingSegments.map(\.colorIndex) == [0])
		#expect(items[1].incomingSegments.map(\.colorIndex) == [0])
	}

	@Test
	func testCancellableBuildStopsWhenTaskIsCancelled() async {
		let commits = (0..<10_000).map {
			makeCommit(hash: "commit-\($0)", parents: [])
		}
		let task = Task.detached {
			try CommitGraphLayoutBuilder.buildCancellable(commits: commits)
		}

		task.cancel()

		do {
			_ = try await task.value
			Issue.record("Cancelled graph layout completed")
		} catch is CancellationError {
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
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
