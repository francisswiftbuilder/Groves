struct CommitAvailability: Equatable {
	let hasStagedChanges: Bool
	let hasCommits: Bool
	let isDetached: Bool

	static let empty = CommitAvailability(
		hasStagedChanges: false,
		hasCommits: false,
		isDetached: false
	)
}
