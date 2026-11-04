import Foundation
import FoundationModels

@Generable
struct GeneratedConventionalCommitPlan {
	@Generable
	struct Commit {
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
				"One concise subject in the language required by the session instructions. No type, scope, attribution or newline."
		)
		var subject: String
		@Guide(
			description: "A short explanation in the subject’s language. No attribution or trailers.")
		var body: String
		@Guide(
			description:
				"Related integer CHANGE IDs. Use every supplied ID exactly once across all commits.")
		var changeIDs: [Int]
	}

	static let subjectPattern =
		"^(feat|fix|refactor|perf|docs|style|test|build|ci|chore|revert)(\\([^\\r\\n)]+\\))?!?:\\s"

	@Guide(
		description:
			"Group related changes into a few logical commits, including changes in different files.")
	var commits: [Commit]

	var plan: GeneratedCommitPlan {
		GeneratedCommitPlan(
			commits: commits.map { commit in
				let subject = commit.subject.trimmingCharacters(in: .whitespacesAndNewlines)
				let scope = commit.scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				let prefix = scope.isEmpty ? commit.type : "\(commit.type)(\(scope))"
				let formatted =
					subject.range(of: Self.subjectPattern, options: .regularExpression) == nil
					? prefix + ": " + subject : subject
				return .init(subject: formatted, body: commit.body, changeIDs: commit.changeIDs)
			})
	}
}
