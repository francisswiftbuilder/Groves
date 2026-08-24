import Foundation

enum CommitDiffFileParser {
	static func parse(_ diff: String) -> [CommitDiffFile] {
		let sections =
			diff
			.components(separatedBy: "\ndiff --git ")
			.enumerated()
			.map { index, section in
				index == 0 ? section : "diff --git \(section)"
			}
			.filter { $0.hasPrefix("diff --git ") }

		return sections.enumerated().compactMap { index, section in
			guard let path = path(in: section) else { return nil }
			let lines = DiffParser.parseSourceLines(section)
			return CommitDiffFile(
				id: "\(index)-\(path)",
				path: path,
				diff: section,
				additions: lines.count { $0.kind == .addition },
				deletions: lines.count { $0.kind == .deletion }
			)
		}
	}

	private static func path(in section: String) -> String? {
		let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
		if let newPath = lines.first(where: { $0.hasPrefix("+++ b/") }) {
			return String(newPath.dropFirst(6))
		}
		if let oldPath = lines.first(where: { $0.hasPrefix("--- a/") }) {
			return String(oldPath.dropFirst(6))
		}
		guard let header = lines.first else { return nil }
		let components = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
		guard components.count == 4 else { return nil }
		let path = String(components[3])
		return path.hasPrefix("b/") ? String(path.dropFirst(2)) : path
	}
}
