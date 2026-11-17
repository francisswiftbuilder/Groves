import FoundationModels

@Generable
struct GeneratedConventionalCommitMessage {
	@Guide(
		description: "The Conventional Commit type.",
		.anyOf([
			"feat", "fix", "refactor", "perf", "docs", "style", "test", "build", "ci", "chore",
			"revert",
		]))
	var type: String
	@Guide(description: "An untranslated code scope from the repository examples, or nil.")
	var scope: String?
	@Guide(
		description:
			"One concise subject in the required language. No type, scope, attribution or newline."
	)
	var subject: String
	@Guide(description: "A short explanation in the subject’s language. No attribution or trailers.")
	var body: String

	var plan: GeneratedCommitPlan {
		GeneratedConventionalCommitPlan(
			commits: [.init(type: type, scope: scope, subject: subject, body: body, changeIDs: [])]
		).plan
	}
}
