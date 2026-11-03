import FoundationModels

@Generable
struct GeneratedCommitPlan {
	@Generable
	struct Commit {
		@Guide(
			description:
				"One concise subject line describing the current changes, in the specified output language. Follow the history’s format. Keep Conventional Commit types and code scopes untranslated. No body text or newline here."
		)
		var subject: String
		@Guide(
			description:
				"A short explanation of the current changes in the same output language as the subject. Follow the history’s body style. No attribution or trailers."
		)
		var body: String
		@Guide(
			description:
				"The integer IDs of the related change blocks. Use every supplied ID exactly once across all commits."
		)
		var changeIDs: [Int]
	}

	@Guide(
		description:
			"Separate commits for independent tasks. Group related changes, including changes in different files."
	)
	var commits: [Commit]
}
