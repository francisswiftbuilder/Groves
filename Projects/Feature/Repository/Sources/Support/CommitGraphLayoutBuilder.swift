import DomainGitInterface
import Foundation

enum CommitGraphLayoutBuilder {
	static func build(commits: [GitCommit]) -> [CommitGraphItem] {
		var lanes: [String] = []

		return commits.map { commit in
			let lane: Int
			if let existingLane = lanes.firstIndex(of: commit.hash) {
				lane = existingLane
			} else {
				lanes.insert(commit.hash, at: 0)
				lane = 0
			}

			let topLanes = lanes
			lanes.remove(at: lane)

			for parentHash in commit.parentHashes.reversed() where !lanes.contains(parentHash) {
				lanes.insert(parentHash, at: min(lane, lanes.count))
			}

			return CommitGraphItem(
				commit: commit,
				topLanes: topLanes,
				bottomLanes: lanes,
				lane: lane
			)
		}
	}
}
