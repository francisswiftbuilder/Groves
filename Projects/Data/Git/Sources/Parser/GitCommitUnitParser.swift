import CryptoKit
import DomainGitInterface
import Foundation

enum GitCommitUnitParser {
	static func parse(_ diff: String, path: String) throws -> [GitCommitUnit] {
		guard !diff.isEmpty else { return [] }
		let lines = diff.components(separatedBy: "\n")
		let hunks = lines.compactMap { line -> GitDiffHunkSelection? in
			guard line.hasPrefix("@@ ") else { return nil }
			let ranges = line.split(separator: " ")
			guard ranges.count >= 3,
				let old = Int(ranges[1].dropFirst().split(separator: ",")[0]),
				let new = Int(ranges[2].dropFirst().split(separator: ",")[0])
			else { return nil }
			return GitDiffHunkSelection(oldStartLine: old, newStartLine: new)
		}
		let isAtomic =
			hunks.isEmpty
			|| lines.contains {
				$0.hasPrefix("new file mode ") || $0.hasPrefix("deleted file mode ")
					|| $0.hasPrefix("old mode ") || $0.hasPrefix("rename from ")
					|| $0.hasPrefix("GIT binary patch") || $0.contains("Subproject commit ")
			}
		if isAtomic {
			return [
				GitCommitUnit(id: fingerprint(path + "\n" + diff), path: path, patch: diff, hunk: nil)
			]
		}
		return try hunks.map { hunk in
			let patch = try GitHunkPatchBuilder.makePatch(from: diff, selection: hunk)
			let body = patch.components(separatedBy: "\n").drop { !$0.hasPrefix("@@ ") }.dropFirst()
			let key = path + "\n\(hunk.newStartLine)\n" + body.joined(separator: "\n")
			return GitCommitUnit(id: fingerprint(key), path: path, patch: patch, hunk: hunk)
		}
	}

	static func combinedPatch(for units: [GitCommitUnit]) throws -> String {
		var patches: [String] = []
		for path in Set(units.map(\.path)).sorted() {
			let fileUnits = units.filter { $0.path == path }
			if fileUnits.contains(where: { $0.hunk == nil }) {
				guard fileUnits.count == 1, let unit = fileUnits.first else {
					throw GitCommitPlanError.invalidPlan
				}
				patches.append(unit.patch)
				continue
			}
			let sorted = fileUnits.sorted { ($0.hunk?.oldStartLine ?? 0) < ($1.hunk?.oldStartLine ?? 0) }
			guard let first = sorted.first else { continue }
			let header = first.patch.components(separatedBy: "\n").prefix { !$0.hasPrefix("@@ ") }
			var lines = Array(header)
			for unit in sorted {
				var body = Array(unit.patch.components(separatedBy: "\n").drop { !$0.hasPrefix("@@ ") })
				while body.last == "" { body.removeLast() }
				lines.append(contentsOf: body)
			}
			patches.append(lines.joined(separator: "\n"))
		}
		return patches.joined(separator: "\n") + "\n"
	}

	static func fingerprint(_ value: String) -> String {
		SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
	}
}
