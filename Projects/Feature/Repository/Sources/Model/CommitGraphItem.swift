import DomainGitInterface

struct CommitGraphColumn: Identifiable, Hashable, Sendable {
	let id: Int
	let targetHash: String
	let colorIndex: Int
}

struct CommitGraphSegment: Hashable, Sendable {
	let columnID: CommitGraphColumn.ID
	let fromLane: Int
	let toLane: Int
	let colorIndex: Int
}

struct CommitGraphItem: Identifiable, Hashable, Sendable {
	let commit: GitCommit
	let topColumns: [CommitGraphColumn]
	let bottomColumns: [CommitGraphColumn]
	let incomingSegments: [CommitGraphSegment]
	let outgoingSegments: [CommitGraphSegment]
	let lane: Int
	let nodeColorIndex: Int

	var id: String { commit.id }

	var visibleLaneCount: Int {
		max(1, topColumns.count, bottomColumns.count, lane + 1)
	}
}
