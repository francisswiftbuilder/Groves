import DomainGitInterface

struct CommitGraphItem: Identifiable, Hashable, Sendable {
	let commit: GitCommit
	let topLanes: [String]
	let bottomLanes: [String]
	let topLaneColorIndices: [Int]
	let bottomLaneColorIndices: [Int]
	let lane: Int

	var id: String { commit.id }

	var visibleLaneCount: Int {
		max(1, topLanes.count, bottomLanes.count, lane + 1)
	}
}
