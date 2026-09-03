import DomainGitInterface
import Foundation

enum GitHunkPatchBuilder {
	static func makePatch(
		from diff: String,
		selection: GitDiffHunkSelection
	) throws -> String {
		let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard
			let oldFileHeaderIndex = lines.firstIndex(where: { $0.hasPrefix("--- ") }),
			let newFileHeaderIndex = lines[oldFileHeaderIndex...]
				.firstIndex(where: { $0.hasPrefix("+++ ") })
		else {
			throw GitRepositoryError.invalidOutput
		}

		guard
			let hunkStartIndex = lines[newFileHeaderIndex...].firstIndex(where: { line in
				guard let start = parseHunkStart(line) else { return false }
				return start.old == selection.oldStartLine && start.new == selection.newStartLine
			})
		else {
			throw GitRepositoryError.invalidOutput
		}

		let nextSearchIndex = lines.index(after: hunkStartIndex)
		let nextHunkIndex =
			nextSearchIndex < lines.endIndex
			? lines[nextSearchIndex...].firstIndex(where: { $0.hasPrefix("@@ ") }) ?? lines.endIndex
			: lines.endIndex
		var patchLines = Array(lines[...newFileHeaderIndex])
		patchLines.append(contentsOf: lines[hunkStartIndex..<nextHunkIndex])
		return patchLines.joined(separator: "\n") + "\n"
	}

	private static func parseHunkStart(_ line: String) -> (old: Int, new: Int)? {
		guard line.hasPrefix("@@ ") else { return nil }
		let components = line.split(separator: " ")
		guard components.count >= 3,
			let old = parseRangeStart(components[1], prefix: "-"),
			let new = parseRangeStart(components[2], prefix: "+")
		else { return nil }
		return (old, new)
	}

	private static func parseRangeStart(_ range: Substring, prefix: Character) -> Int? {
		guard range.first == prefix else { return nil }
		return Int(range.dropFirst().split(separator: ",", maxSplits: 1)[0])
	}
}
