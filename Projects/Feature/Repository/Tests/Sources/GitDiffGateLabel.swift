import DomainGitInterface
import Foundation

enum GitDiffGateLabel {
	static func workingTree(options: GitDiffOptions) -> String {
		"workingTree-\(options.ignoresWhitespace)"
	}

	static func stash(options: GitDiffOptions) -> String {
		"stash-\(options.ignoresWhitespace)"
	}

	static func stashDiff(options: GitDiffOptions) -> String {
		"stash diff ignoresWhitespace=\(options.ignoresWhitespace)"
	}

	static func conflictContent(path: String) -> String {
		"conflictContent-\(path)"
	}
}
