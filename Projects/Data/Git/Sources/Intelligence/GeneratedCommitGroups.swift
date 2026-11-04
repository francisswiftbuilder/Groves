import FoundationModels

@Generable
struct GeneratedCommitGroups {
	@Generable
	struct Group {
		@Guide(description: "One short line describing the logical task in at most 16 words.")
		var description: String
		@Guide(
			description: "Related CHANGE IDs. Include each supplied ID exactly once across all groups.",
			.minimumCount(1))
		var changeIDs: [Int]
	}

	@Guide(
		description: "A few coherent logical tasks. Keep related changes together across files.",
		.minimumCount(1))
	var groups: [Group]

	var plan: GeneratedCommitPlan {
		.init(commits: groups.map { .init(subject: $0.description, body: "", changeIDs: $0.changeIDs) })
	}
}
