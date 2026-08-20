import DomainGitInterface
import Foundation

enum CommitGraphLayoutBuilder {
	static func build(commits: [GitCommit]) -> [CommitGraphItem] {
		var lanes: [Lane] = []
		var nextColorIndex = 0

		return commits.map { commit in
			let lane: Int
			if let existingLane = lanes.firstIndex(where: { $0.hash == commit.hash }) {
				lane = existingLane
			} else {
				lanes.insert(
					Lane(hash: commit.hash, colorIndex: nextColorIndex),
					at: 0
				)
				nextColorIndex += 1
				lane = 0
			}

			let topLanes = lanes
			let currentLane = lanes.remove(at: lane)
			var insertedParentCount = 0

			for (parentIndex, parentHash) in commit.parentHashes.enumerated()
			where !lanes.contains(where: { $0.hash == parentHash }) {
				let colorIndex: Int
				if parentIndex == 0 {
					colorIndex = currentLane.colorIndex
				} else {
					colorIndex = nextColorIndex
					nextColorIndex += 1
				}

				lanes.insert(
					Lane(hash: parentHash, colorIndex: colorIndex),
					at: min(lane + insertedParentCount, lanes.count)
				)
				insertedParentCount += 1
			}

			return CommitGraphItem(
				commit: commit,
				topLanes: topLanes.map(\.hash),
				bottomLanes: lanes.map(\.hash),
				topLaneColorIndices: topLanes.map(\.colorIndex),
				bottomLaneColorIndices: lanes.map(\.colorIndex),
				lane: lane
			)
		}
	}

	private struct Lane: Hashable {
		let hash: String
		let colorIndex: Int
	}
}
