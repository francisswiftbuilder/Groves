import DomainGitInterface
import SwiftUI

enum DiffParser {
	static func parseSourceLines(_ diff: String) -> [DiffLine] {
		parse(diff).filter(\.isSourceLine)
	}

	static func parse(_ diff: String) -> [DiffLine] {
		let sourceLines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var oldLineNumber: Int?
		var newLineNumber: Int?
		var lines: [DiffLine] = []

		for (number, text) in sourceLines.enumerated() {
			if let hunkStart = parseHunkStart(text) {
				oldLineNumber = hunkStart.old
				newLineNumber = hunkStart.new
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: nil,
						newLineNumber: nil,
						kind: .hunk,
						selection: nil,
						hunkSelection: GitDiffHunkSelection(
							oldStartLine: hunkStart.old,
							newStartLine: hunkStart.new
						),
						changedRange: nil
					)
				)
				continue
			}

			guard let currentOldLineNumber = oldLineNumber,
				let currentNewLineNumber = newLineNumber
			else {
				lines.append(metadataLine(number: number, text: text))
				continue
			}

			if text.hasPrefix("-") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: nil,
						kind: .deletion,
						selection: nil,
						hunkSelection: nil,
						changedRange: nil
					)
				)
				oldLineNumber = currentOldLineNumber + 1
				continue
			}

			if text.hasPrefix("+") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: nil,
						newLineNumber: currentNewLineNumber,
						kind: .addition,
						selection: nil,
						hunkSelection: nil,
						changedRange: nil
					)
				)
				newLineNumber = currentNewLineNumber + 1
				continue
			}

			if text.hasPrefix(" ") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: currentNewLineNumber,
						kind: .context,
						selection: nil,
						hunkSelection: nil,
						changedRange: nil
					)
				)
				oldLineNumber = currentOldLineNumber + 1
				newLineNumber = currentNewLineNumber + 1
				continue
			}

			lines.append(metadataLine(number: number, text: text))
		}

		return pairChangedLines(lines)
	}

	private static func pairChangedLines(_ sourceLines: [DiffLine]) -> [DiffLine] {
		var lines = sourceLines
		var index = 0

		while index < lines.count {
			guard isChangedLine(lines[index]) else {
				index += 1
				continue
			}

			let startIndex = index
			while index < lines.count, isChangedLine(lines[index]) {
				index += 1
			}

			let changedIndices = Array(startIndex..<index)
			let deletionIndices = changedIndices.filter { lines[$0].kind == .deletion }
			let additionIndices = changedIndices.filter { lines[$0].kind == .addition }
			let pairedCount = min(deletionIndices.count, additionIndices.count)

			for pairIndex in 0..<pairedCount {
				let deletionIndex = deletionIndices[pairIndex]
				let additionIndex = additionIndices[pairIndex]
				let selection = GitDiffLineSelection(
					oldLineNumber: lines[deletionIndex].oldLineNumber,
					newLineNumber: lines[additionIndex].newLineNumber
				)
				lines[deletionIndex].selection = selection
				lines[additionIndex].selection = selection
				lines[deletionIndex].showsAction = true
				let changedRanges = changedRanges(
					old: lines[deletionIndex].sourceText,
					new: lines[additionIndex].sourceText
				)
				lines[deletionIndex].changedRange = changedRanges.old
				lines[additionIndex].changedRange = changedRanges.new
			}

			for deletionIndex in deletionIndices.dropFirst(pairedCount) {
				lines[deletionIndex].selection = GitDiffLineSelection(
					oldLineNumber: lines[deletionIndex].oldLineNumber,
					newLineNumber: nil
				)
				lines[deletionIndex].showsAction = true
			}

			for additionIndex in additionIndices.dropFirst(pairedCount) {
				lines[additionIndex].selection = GitDiffLineSelection(
					oldLineNumber: nil,
					newLineNumber: lines[additionIndex].newLineNumber
				)
				lines[additionIndex].showsAction = true
			}
		}

		return lines
	}

	private static func isChangedLine(_ line: DiffLine) -> Bool {
		line.kind == .addition || line.kind == .deletion
	}

	private static func changedRanges(
		old: String,
		new: String
	) -> (old: DiffTextRange?, new: DiffTextRange?) {
		let oldCharacters = Array(old)
		let newCharacters = Array(new)
		let sharedCount = min(oldCharacters.count, newCharacters.count)
		var prefixCount = 0
		while prefixCount < sharedCount,
			oldCharacters[prefixCount] == newCharacters[prefixCount]
		{
			prefixCount += 1
		}

		var suffixCount = 0
		while suffixCount < sharedCount - prefixCount,
			oldCharacters[oldCharacters.count - suffixCount - 1]
				== newCharacters[newCharacters.count - suffixCount - 1]
		{
			suffixCount += 1
		}

		return (
			makeChangedRange(
				characterCount: oldCharacters.count,
				prefixCount: prefixCount,
				suffixCount: suffixCount
			),
			makeChangedRange(
				characterCount: newCharacters.count,
				prefixCount: prefixCount,
				suffixCount: suffixCount
			)
		)
	}

	private static func makeChangedRange(
		characterCount: Int,
		prefixCount: Int,
		suffixCount: Int
	) -> DiffTextRange? {
		let length = characterCount - prefixCount - suffixCount
		guard length > 0 else { return nil }
		return DiffTextRange(location: prefixCount, length: length)
	}

	private static func metadataLine(number: Int, text: String) -> DiffLine {
		DiffLine(
			number: number,
			text: text,
			oldLineNumber: nil,
			newLineNumber: nil,
			kind: .metadata,
			selection: nil,
			hunkSelection: nil,
			changedRange: nil
		)
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
