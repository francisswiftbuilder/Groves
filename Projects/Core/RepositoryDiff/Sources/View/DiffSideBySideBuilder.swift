import Foundation

enum DiffSideBySideBuilder {
	static func build(from document: DiffDocument) -> [DiffSideBySideRow] {
		(try? build(from: document, checksCancellation: false)) ?? []
	}

	static func buildCancellable(from document: DiffDocument) throws -> [DiffSideBySideRow] {
		try build(from: document, checksCancellation: true)
	}

	private static func build(
		from document: DiffDocument,
		checksCancellation: Bool
	) throws -> [DiffSideBySideRow] {
		var rows: [DiffSideBySideRow] = []
		var index = 0

		while index < document.lines.count {
			if checksCancellation, index.isMultiple(of: 256) {
				try Task.checkCancellation()
			}
			let line = document.lines[index]
			switch line.kind {
			case .metadata, .hunk:
				rows.append(
					DiffSideBySideRow(
						id: line.id,
						fullWidthLine: line,
						oldLine: nil,
						newLine: nil
					)
				)
				index += 1
			case .context:
				rows.append(
					DiffSideBySideRow(
						id: line.id,
						fullWidthLine: nil,
						oldLine: line,
						newLine: line
					)
				)
				index += 1
			case .addition, .deletion:
				let startIndex = index
				while index < document.lines.count,
					document.lines[index].kind == .addition
						|| document.lines[index].kind == .deletion
				{
					index += 1
				}
				rows.append(
					contentsOf: try changedRows(
						Array(document.lines[startIndex..<index]),
						checksCancellation: checksCancellation
					)
				)
			}
		}

		return rows
	}

	private static func changedRows(
		_ lines: [DiffLine],
		checksCancellation: Bool
	) throws -> [DiffSideBySideRow] {
		let deletions = lines.filter { $0.kind == .deletion }
		let additions = lines.filter { $0.kind == .addition }
		if deletions.count == 1, additions.count == 1 {
			return indexPairedRows(deletions: deletions, additions: additions)
		}
		guard deletions.count <= 64, additions.count <= 64,
			lines.allSatisfy({ $0.sourceText.count <= 512 })
		else {
			return indexPairedRows(deletions: deletions, additions: additions)
		}
		return try alignedRows(
			deletions: deletions,
			additions: additions,
			checksCancellation: checksCancellation
		)
	}

	private static func indexPairedRows(
		deletions: [DiffLine],
		additions: [DiffLine]
	) -> [DiffSideBySideRow] {
		let rowCount = max(deletions.count, additions.count)

		return (0..<rowCount).map { index in
			let oldLine = deletions.indices.contains(index) ? deletions[index] : nil
			let newLine = additions.indices.contains(index) ? additions[index] : nil
			return DiffSideBySideRow(
				id: oldLine?.id ?? newLine?.id ?? index,
				fullWidthLine: nil,
				oldLine: oldLine,
				newLine: newLine
			)
		}
	}

	private static func alignedRows(
		deletions: [DiffLine],
		additions: [DiffLine],
		checksCancellation: Bool
	) throws -> [DiffSideBySideRow] {
		let gapPenalty = -0.4
		var scores = Array(
			repeating: Array(repeating: 0.0, count: additions.count + 1),
			count: deletions.count + 1
		)
		var choices = Array(
			repeating: Array(repeating: 0, count: additions.count + 1),
			count: deletions.count + 1
		)
		if !deletions.isEmpty {
			for oldIndex in 1...deletions.count {
				scores[oldIndex][0] = Double(oldIndex) * gapPenalty
				choices[oldIndex][0] = 1
			}
		}
		if !additions.isEmpty {
			for newIndex in 1...additions.count {
				scores[0][newIndex] = Double(newIndex) * gapPenalty
				choices[0][newIndex] = 2
			}
		}

		if !deletions.isEmpty, !additions.isEmpty {
			for oldIndex in 1...deletions.count {
				if checksCancellation {
					try Task.checkCancellation()
				}
				for newIndex in 1...additions.count {
					let similarity = try editSimilarity(
						deletions[oldIndex - 1].sourceText,
						additions[newIndex - 1].sourceText,
						checksCancellation: checksCancellation
					)
					let paired = scores[oldIndex - 1][newIndex - 1] + similarity * 2 - 1.2
					let deleted = scores[oldIndex - 1][newIndex] + gapPenalty
					let added = scores[oldIndex][newIndex - 1] + gapPenalty
					if paired >= deleted, paired >= added {
						scores[oldIndex][newIndex] = paired
						choices[oldIndex][newIndex] = 0
					} else if deleted >= added {
						scores[oldIndex][newIndex] = deleted
						choices[oldIndex][newIndex] = 1
					} else {
						scores[oldIndex][newIndex] = added
						choices[oldIndex][newIndex] = 2
					}
				}
			}
		}

		var rows: [DiffSideBySideRow] = []
		var oldIndex = deletions.count
		var newIndex = additions.count
		while oldIndex > 0 || newIndex > 0 {
			switch choices[oldIndex][newIndex] {
			case 0 where oldIndex > 0 && newIndex > 0:
				rows.append(makeRow(oldLine: deletions[oldIndex - 1], newLine: additions[newIndex - 1]))
				oldIndex -= 1
				newIndex -= 1
			case 1 where oldIndex > 0:
				rows.append(makeRow(oldLine: deletions[oldIndex - 1], newLine: nil))
				oldIndex -= 1
			default:
				rows.append(makeRow(oldLine: nil, newLine: additions[newIndex - 1]))
				newIndex -= 1
			}
		}
		return rows.reversed()
	}

	private static func makeRow(oldLine: DiffLine?, newLine: DiffLine?) -> DiffSideBySideRow {
		DiffSideBySideRow(
			id: oldLine?.id ?? newLine?.id ?? 0,
			fullWidthLine: nil,
			oldLine: oldLine,
			newLine: newLine
		)
	}

	private static func editSimilarity(
		_ oldText: String,
		_ newText: String,
		checksCancellation: Bool
	) throws -> Double {
		if oldText == newText { return 1 }
		let oldCharacters = Array(oldText)
		let newCharacters = Array(newText)
		let maximumCount = max(oldCharacters.count, newCharacters.count)
		guard maximumCount > 0 else { return 1 }

		var prefixCount = 0
		while prefixCount < min(oldCharacters.count, newCharacters.count),
			oldCharacters[prefixCount] == newCharacters[prefixCount]
		{
			prefixCount += 1
		}
		var oldEnd = oldCharacters.count
		var newEnd = newCharacters.count
		while oldEnd > prefixCount, newEnd > prefixCount,
			oldCharacters[oldEnd - 1] == newCharacters[newEnd - 1]
		{
			oldEnd -= 1
			newEnd -= 1
		}
		let oldMiddle = Array(oldCharacters[prefixCount..<oldEnd])
		let newMiddle = Array(newCharacters[prefixCount..<newEnd])
		let distance = try editDistance(
			oldMiddle,
			newMiddle,
			checksCancellation: checksCancellation
		)
		return max(0, 1 - Double(distance) / Double(maximumCount))
	}

	private static func editDistance(
		_ lhs: [Character],
		_ rhs: [Character],
		checksCancellation: Bool
	) throws -> Int {
		if lhs.isEmpty { return rhs.count }
		if rhs.isEmpty { return lhs.count }
		var previous = Array(0...rhs.count)
		var current = Array(repeating: 0, count: rhs.count + 1)
		for lhsIndex in lhs.indices {
			if checksCancellation, lhsIndex.isMultiple(of: 32) {
				try Task.checkCancellation()
			}
			current[0] = lhsIndex + 1
			for rhsIndex in rhs.indices {
				let substitutionCost = lhs[lhsIndex] == rhs[rhsIndex] ? 0 : 1
				current[rhsIndex + 1] = min(
					previous[rhsIndex + 1] + 1,
					current[rhsIndex] + 1,
					previous[rhsIndex] + substitutionCost
				)
			}
			swap(&previous, &current)
		}
		return previous[rhs.count]
	}
}
