import DomainGitInterface
import Foundation

enum GitConflictMarkerParser {
	static func parse(_ contents: String) -> [GitConflictHunk] {
		let lines = splitLines(contents)
		var hunks: [GitConflictHunk] = []
		var index = 0

		while index < lines.count {
			guard let markerLength = openingMarkerLength(lines[index]) else {
				index += 1
				continue
			}
			guard
				let parsed = parseHunk(
					in: lines,
					startingAt: index,
					markerLength: markerLength
				)
			else {
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
		let separator = lineSeparator(in: contents)
		let lines = contents.components(separatedBy: separator)
		var output: [String] = []
		var index = 0
		var currentHunkIndex = 0

		while index < lines.count {
			guard let markerLength = openingMarkerLength(lines[index]),
				let parsed = parseHunk(
					in: lines,
					startingAt: index,
					markerLength: markerLength
				)
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
				return output.joined(separator: separator)
			}

			output.append(contentsOf: lines[index...parsed.endIndex])
			index = parsed.endIndex + 1
			currentHunkIndex += 1
		}

		throw GitRepositoryError.invalidOutput
	}

	private static func parseHunk(
		in lines: [String],
		startingAt startIndex: Int,
		markerLength: Int
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
			let line = lines[index]
			if isMarkerLike(line, character: "<") {
				return nil
			}
			if isMarkerLike(line, character: "|") {
				guard baseIndex == nil, separatorIndex == nil,
					isLabeledMarker(line, character: "|", length: markerLength)
				else {
					return nil
				}
				baseIndex = index
			} else if isMarkerLike(line, character: "=") {
				guard separatorIndex == nil,
					line == String(repeating: "=", count: markerLength)
				else {
					return nil
				}
				separatorIndex = index
			} else if isMarkerLike(line, character: ">") {
				guard separatorIndex != nil,
					isLabeledMarker(line, character: ">", length: markerLength)
				else {
					return nil
				}
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

	private static func splitLines(_ contents: String) -> [String] {
		contents.components(separatedBy: lineSeparator(in: contents))
	}

	private static func lineSeparator(in contents: String) -> String {
		contents.contains("\r\n") ? "\r\n" : "\n"
	}

	private static func openingMarkerLength(_ line: String) -> Int? {
		let length = prefixLength(in: line, character: "<")
		guard length >= 7, isLabeledMarker(line, character: "<", length: length) else {
			return nil
		}
		return length
	}

	private static func isMarkerLike(_ line: String, character: Character) -> Bool {
		prefixLength(in: line, character: character) >= 7
	}

	private static func isLabeledMarker(
		_ line: String,
		character: Character,
		length: Int
	) -> Bool {
		guard prefixLength(in: line, character: character) == length else { return false }
		let suffix = line.dropFirst(length)
		return suffix.isEmpty || suffix.first?.isWhitespace == true
	}

	private static func prefixLength(in line: String, character: Character) -> Int {
		line.prefix(while: { $0 == character }).count
	}
}
