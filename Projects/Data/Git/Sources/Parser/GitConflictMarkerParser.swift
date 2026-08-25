import DomainGitInterface
import Foundation

enum GitConflictMarkerParser {
	static func parse(_ contents: String) -> [GitConflictHunk] {
		let lines = contents.components(separatedBy: "\n")
		var hunks: [GitConflictHunk] = []
		var index = 0

		while index < lines.count {
			guard lines[index].hasPrefix("<<<<<<<") else {
				index += 1
				continue
			}
			guard let parsed = parseHunk(in: lines, startingAt: index) else {
				index += 1
				continue
			}
			hunks.append(
				GitConflictHunk(
					index: hunks.count,
					base: parsed.base,
					current: parsed.current,
					incoming: parsed.incoming
				)
			)
			index = parsed.endIndex + 1
		}

		return hunks
	}

	static func resolve(
		_ hunkIndex: Int,
		using resolution: GitConflictHunkResolution,
		in contents: String
	) throws -> String {
		let lines = contents.components(separatedBy: "\n")
		var output: [String] = []
		var index = 0
		var currentHunkIndex = 0

		while index < lines.count {
			guard lines[index].hasPrefix("<<<<<<<"),
				let parsed = parseHunk(in: lines, startingAt: index)
			else {
				output.append(lines[index])
				index += 1
				continue
			}

			if currentHunkIndex == hunkIndex {
				switch resolution {
				case .current:
					output.append(contentsOf: parsed.currentLines)
				case .incoming:
					output.append(contentsOf: parsed.incomingLines)
				case .both:
					output.append(contentsOf: parsed.currentLines)
					output.append(contentsOf: parsed.incomingLines)
				}
				let remainingStartIndex = parsed.endIndex + 1
				if remainingStartIndex < lines.count {
					output.append(contentsOf: lines[remainingStartIndex...])
				}
				return output.joined(separator: "\n")
			}

			output.append(contentsOf: lines[index...parsed.endIndex])
			index = parsed.endIndex + 1
			currentHunkIndex += 1
		}

		throw GitRepositoryError.invalidOutput
	}

	private static func parseHunk(
		in lines: [String],
		startingAt startIndex: Int
	) -> (
		base: String?,
		current: String,
		incoming: String,
		currentLines: [String],
		incomingLines: [String],
		endIndex: Int
	)? {
		var separatorIndex: Int?
		var baseIndex: Int?
		var endIndex: Int?
		var index = startIndex + 1

		while index < lines.count {
			if lines[index].hasPrefix("|||||||") {
				baseIndex = index
			} else if lines[index] == "=======" {
				separatorIndex = index
			} else if lines[index].hasPrefix(">>>>>>>") {
				endIndex = index
				break
			}
			index += 1
		}

		guard let separatorIndex, let endIndex else { return nil }
		let currentEndIndex = baseIndex ?? separatorIndex
		let currentLines = Array(lines[(startIndex + 1)..<currentEndIndex])
		let baseLines = baseIndex.map { Array(lines[($0 + 1)..<separatorIndex]) }
		let incomingLines = Array(lines[(separatorIndex + 1)..<endIndex])
		return (
			base: baseLines?.joined(separator: "\n"),
			current: currentLines.joined(separator: "\n"),
			incoming: incomingLines.joined(separator: "\n"),
			currentLines: currentLines,
			incomingLines: incomingLines,
			endIndex: endIndex
		)
	}
}
