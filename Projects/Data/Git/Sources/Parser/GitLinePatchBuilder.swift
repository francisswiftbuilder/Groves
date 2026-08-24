import DomainGitInterface
import Foundation

enum GitLinePatchBuilder {
	static func makePatch(
		from diff: String,
		selection: GitDiffLineSelection
	) throws -> String {
		let lines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard
			let oldFileHeaderIndex = lines.firstIndex(where: { $0.hasPrefix("--- ") }),
			let newFileHeaderIndex = lines[oldFileHeaderIndex...]
				.firstIndex(where: { $0.hasPrefix("+++ ") }),
			!lines[oldFileHeaderIndex].hasSuffix("/dev/null"),
			!lines[newFileHeaderIndex].hasSuffix("/dev/null")
		else {
			throw GitRepositoryError.invalidOutput
		}

		var oldLineNumber: Int?
		var newLineNumber: Int?
		var deletion: PatchLine?
		var addition: PatchLine?

		for index in lines.indices where index > newFileHeaderIndex {
			let line = lines[index]
			if let hunkStart = parseHunkStart(line) {
				oldLineNumber = hunkStart.old
				newLineNumber = hunkStart.new
				continue
			}

			guard let currentOldLineNumber = oldLineNumber,
				let currentNewLineNumber = newLineNumber
			else { continue }

			if line.hasPrefix("-") {
				if selection.oldLineNumber == currentOldLineNumber {
					deletion = PatchLine(
						text: line,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: currentNewLineNumber,
						hasNoNewlineMarker: hasNoNewlineMarker(after: index, in: lines)
					)
				}
				oldLineNumber = currentOldLineNumber + 1
				continue
			}

			if line.hasPrefix("+") {
				if selection.newLineNumber == currentNewLineNumber {
					addition = PatchLine(
						text: line,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: currentNewLineNumber,
						hasNoNewlineMarker: hasNoNewlineMarker(after: index, in: lines)
					)
				}
				newLineNumber = currentNewLineNumber + 1
				continue
			}

			if line.hasPrefix(" ") {
				oldLineNumber = currentOldLineNumber + 1
				newLineNumber = currentNewLineNumber + 1
			}
		}

		guard selection.oldLineNumber == nil || deletion != nil,
			selection.newLineNumber == nil || addition != nil,
			deletion != nil || addition != nil
		else {
			throw GitRepositoryError.invalidOutput
		}

		let oldStart = deletion?.oldLineNumber ?? addition?.oldLineNumber
		let newStart = addition?.newLineNumber ?? deletion?.newLineNumber
		guard let oldStart, let newStart else {
			throw GitRepositoryError.invalidOutput
		}

		var patchLines = Array(lines[...newFileHeaderIndex])
		patchLines.append(
			"@@ -\(oldStart),\(deletion == nil ? 0 : 1) +\(newStart),\(addition == nil ? 0 : 1) @@"
		)
		if let deletion {
			patchLines.append(deletion.text)
			if deletion.hasNoNewlineMarker {
				patchLines.append("\\ No newline at end of file")
			}
		}
		if let addition {
			patchLines.append(addition.text)
			if addition.hasNoNewlineMarker {
				patchLines.append("\\ No newline at end of file")
			}
		}

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

	private static func hasNoNewlineMarker(after index: Int, in lines: [String]) -> Bool {
		let markerIndex = index + 1
		return lines.indices.contains(markerIndex)
			&& lines[markerIndex] == "\\ No newline at end of file"
	}
}
