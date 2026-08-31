import Foundation

public enum CommitDiffFileParser {
	public static func parse(_ diff: String) -> [CommitDiffFile] {
		(try? parse(diff, checksCancellation: false)) ?? []
	}

	public static func parseCancellable(_ diff: String) throws -> [CommitDiffFile] {
		try parse(diff, checksCancellation: true)
	}

	private static func parse(
		_ diff: String,
		checksCancellation: Bool
	) throws -> [CommitDiffFile] {
		var sections: [String] = []
		for (index, section) in diff.components(separatedBy: "\ndiff --git ").enumerated() {
			if checksCancellation {
				try Task.checkCancellation()
			}
			let normalizedSection = index == 0 ? section : "diff --git \(section)"
			if normalizedSection.hasPrefix("diff --git ") {
				sections.append(normalizedSection)
			}
		}

		var files: [CommitDiffFile] = []
		for (index, section) in sections.enumerated() {
			if checksCancellation {
				try Task.checkCancellation()
			}
			guard let path = path(in: section) else { continue }
			let previousPath = previousPath(in: section, currentPath: path)
			let lines =
				if checksCancellation {
					try DiffParser.parseSourceLinesCancellable(section)
				} else {
					DiffParser.parseSourceLines(section)
				}
			files.append(
				CommitDiffFile(
					id: "\(index)-\(path)",
					path: path,
					previousPath: previousPath,
					diff: section,
					additions: lines.count { $0.kind == .addition },
					deletions: lines.count { $0.kind == .deletion }
				)
			)
		}
		return files
	}

	private static func previousPath(in section: String, currentPath: String) -> String? {
		let lines = section.split(separator: "\n", omittingEmptySubsequences: false)
		if let renamedPath = lines.first(where: { $0.hasPrefix("rename from ") }) {
			let path = String(renamedPath.dropFirst("rename from ".count))
			return path == currentPath ? nil : path
		}
		guard let oldPath = lines.first(where: { $0.hasPrefix("--- a/") }) else { return nil }
		let path = String(oldPath.dropFirst(6))
		return path == currentPath ? nil : path
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
