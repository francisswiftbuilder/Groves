import DomainGitInterface
import Foundation

enum CommitGraphLayoutBuilder {
	static func build(commits: [GitCommit]) -> [CommitGraphItem] {
		(try? build(commits: commits, checksCancellation: false)) ?? []
	}

	static func buildCancellable(commits: [GitCommit]) throws -> [CommitGraphItem] {
		try build(commits: commits, checksCancellation: true)
	}

	private static func build(
		commits: [GitCommit],
		checksCancellation: Bool
	) throws -> [CommitGraphItem] {
		var columns: [CommitGraphColumn] = []
		var nextColumnID = 0
		var nextColorIndex = 0

		return try commits.map { commit in
			if checksCancellation {
				try Task.checkCancellation()
			}
			let lane: Int
			let startsAtCommit: Bool
			if let existingLane = columns.firstIndex(where: { $0.targetHash == commit.hash }) {
				lane = existingLane
				startsAtCommit = false
			} else {
				columns.append(
					CommitGraphColumn(
						id: nextColumnID,
						targetHash: commit.hash,
						colorIndex: nextColorIndex
					)
				)
				nextColumnID += 1
				nextColorIndex += 1
				lane = columns.count - 1
				startsAtCommit = true
			}

			let topColumns = columns
			let currentColumn = columns.remove(at: lane)
			var insertedParentCount = 0
			var parentColumnIDs: [CommitGraphColumn.ID] = []

			for (parentIndex, parentHash) in commit.parentHashes.enumerated() {
				if let existingLane = columns.firstIndex(where: { $0.targetHash == parentHash }) {
					parentColumnIDs.append(columns[existingLane].id)
					continue
				}

				let parentColumn: CommitGraphColumn
				if parentIndex == 0 {
					parentColumn = CommitGraphColumn(
						id: currentColumn.id,
						targetHash: parentHash,
						colorIndex: currentColumn.colorIndex
					)
				} else {
					parentColumn = CommitGraphColumn(
						id: nextColumnID,
						targetHash: parentHash,
						colorIndex: nextColorIndex
					)
					nextColumnID += 1
					nextColorIndex += 1
				}

				columns.insert(
					parentColumn,
					at: min(lane + insertedParentCount, columns.count)
				)
				parentColumnIDs.append(parentColumn.id)
				insertedParentCount += 1
			}

			let incomingSegments: [CommitGraphSegment] = topColumns.enumerated().compactMap {
				lane, column in
				if startsAtCommit, column.id == currentColumn.id {
					return nil
				}
				return CommitGraphSegment(
					columnID: column.id,
					fromLane: lane,
					toLane: lane,
					colorIndex: column.colorIndex
				)
			}
			let continuingSegments: [CommitGraphSegment] = topColumns.enumerated().compactMap {
				topLane, column in
				guard column.id != currentColumn.id else { return nil }
				guard let bottomLane = columns.firstIndex(where: { $0.id == column.id }) else {
					return nil
				}
				return CommitGraphSegment(
					columnID: column.id,
					fromLane: topLane,
					toLane: bottomLane,
					colorIndex: column.colorIndex
				)
			}
			let parentSegments: [CommitGraphSegment] = parentColumnIDs.compactMap { columnID in
				guard let bottomLane = columns.firstIndex(where: { $0.id == columnID }) else {
					return nil
				}
				let column = columns[bottomLane]
				return CommitGraphSegment(
					columnID: column.id,
					fromLane: lane,
					toLane: bottomLane,
					colorIndex: column.colorIndex
				)
			}

			return CommitGraphItem(
				commit: commit,
				topColumns: topColumns,
				bottomColumns: columns,
				incomingSegments: incomingSegments,
				outgoingSegments: continuingSegments + parentSegments,
				lane: lane,
				nodeColorIndex: currentColumn.colorIndex
			)
		}
	}
}
