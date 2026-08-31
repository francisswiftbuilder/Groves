import DomainGitInterface
import Foundation

enum GitDiffGateLabel {
	static func workingTree(options: GitDiffOptions) -> String {
		"workingTree-\(options.ignoresWhitespace)"
	}

	static func commitDiff(hash: String) -> String {
		"commit diff \(hash)"
	}

	static func stash(options: GitDiffOptions) -> String {
		"stash-\(options.ignoresWhitespace)"
	}

	static func stashDiff(options: GitDiffOptions) -> String {
		"stash diff ignoresWhitespace=\(options.ignoresWhitespace)"
	}

	static func stashImageDiff(path: String) -> String {
		"stash image diff \(path)"
	}

	static func conflictContent(path: String) -> String {
		"conflictContent-\(path)"
	}

	static let workingTreeChanges = "workingTreeChanges"

	static func stage(path: String) -> String {
		"stage-\(path)"
	}

	static func applyDiffLine(path: String) -> String {
		"applyDiffLine-\(path)"
	}

	static func resolveConflictHunk(path: String) -> String {
		"resolveConflictHunk-\(path)"
	}
}
