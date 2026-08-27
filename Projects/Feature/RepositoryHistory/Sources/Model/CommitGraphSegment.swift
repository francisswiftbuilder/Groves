import DomainGitInterface

struct CommitGraphSegment: Hashable, Sendable {
	let columnID: CommitGraphColumn.ID
	let fromLane: Int
	let toLane: Int
	let colorIndex: Int
}
