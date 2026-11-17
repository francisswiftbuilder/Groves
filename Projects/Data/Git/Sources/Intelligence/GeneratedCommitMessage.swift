import FoundationModels

@Generable
struct GeneratedCommitMessage {
	@Guide(
		description:
			"One concise subject line in the specified output language and repository format. Keep Conventional Commit types and scopes untranslated. No newline, body text or attribution."
	)
	var subject: String
	@Guide(
		description:
			"A short explanation of the current changes in the subject’s language. No attribution or trailers."
	)
	var body: String

	var plan: GeneratedCommitPlan {
		.init(commits: [.init(subject: subject, body: body, changeIDs: [])])
	}
}
