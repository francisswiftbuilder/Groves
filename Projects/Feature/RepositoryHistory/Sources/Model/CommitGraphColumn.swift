import DomainGitInterface

struct CommitGraphColumn: Identifiable, Hashable, Sendable {
	let id: Int
	let targetHash: String
	let colorIndex: Int
}
