import Foundation

enum DiffSideBySideBuilder {
	static func build(from document: DiffDocument) -> [DiffSideBySideRow] {
		var rows: [DiffSideBySideRow] = []
		var index = 0

		while index < document.lines.count {
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
					contentsOf: changedRows(
						Array(document.lines[startIndex..<index])
					)
				)
			}
		}

		return rows
	}

	private static func changedRows(_ lines: [DiffLine]) -> [DiffSideBySideRow] {
		let deletions = lines.filter { $0.kind == .deletion }
		let additions = lines.filter { $0.kind == .addition }
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
}
