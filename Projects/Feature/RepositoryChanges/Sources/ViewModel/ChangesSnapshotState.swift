import DomainGitInterface

struct ChangesSnapshotState: Equatable {
	let changes: [WorkingTreeChange]
	let amendChanges: [GitAmendChange]
	let conflicts: [GitConflict]

	static let empty = ChangesSnapshotState(
		changes: [],
		amendChanges: [],
		conflicts: []
	)
}
