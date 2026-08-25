import Foundation
import SwiftUI

enum DiffSyntaxHighlighter {
	static func styledText(
		_ text: String,
		filePath: String?,
		kind: DiffLineKind,
		changedRange: DiffTextRange?,
		searchText: String
	) -> AttributedString {
		var result = AttributedString(text.isEmpty ? " " : text)
		applyKeywordHighlighting(to: &result, source: text, filePath: filePath)
		applyLiteralHighlighting(to: &result, source: text)
		applyCommentHighlighting(to: &result, source: text, filePath: filePath)
		if let changedRange {
			apply(
				changedRange,
				to: &result,
				backgroundColor: kind == .addition
					? Color.green.opacity(0.22)
					: Color.red.opacity(0.22)
			)
		}
		applySearchHighlighting(to: &result, source: text, searchText: searchText)
		return result
	}

	private static func applyKeywordHighlighting(
		to result: inout AttributedString,
		source: String,
		filePath: String?
	) {
		let fileExtension = filePath.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
		let keywords: [String]
		switch fileExtension {
		case "swift":
			keywords = [
				"actor", "async", "await", "break", "case", "catch", "class", "continue",
				"default", "defer", "do", "else", "enum", "extension", "false", "for", "func",
				"guard", "if", "import", "in", "init", "let", "nil", "private", "protocol",
				"public", "repeat", "return", "self", "some", "static", "struct", "switch",
				"throw", "throws", "true", "try", "var", "where", "while",
			]
		case "js", "jsx", "ts", "tsx":
			keywords = [
				"async", "await", "break", "case", "catch", "class", "const", "continue",
				"default", "else", "export", "extends", "false", "finally", "for", "function",
				"if", "import", "in", "let", "new", "null", "return", "static", "super",
				"switch", "this", "throw", "true", "try", "typeof", "var", "while",
			]
		case "py":
			keywords = [
				"and", "as", "async", "await", "break", "class", "continue", "def", "del",
				"elif", "else", "except", "False", "finally", "for", "from", "global", "if",
				"import", "in", "is", "lambda", "None", "not", "or", "pass", "raise",
				"return", "True", "try", "while", "with", "yield",
			]
		case "kt", "kts", "java":
			keywords = [
				"abstract", "break", "case", "catch", "class", "continue", "default", "do",
				"else", "enum", "extends", "false", "final", "finally", "for", "fun", "if",
				"implements", "import", "in", "interface", "new", "null", "object", "override",
				"package", "private", "protected", "public", "return", "static", "super",
				"switch", "this", "throw", "true", "try", "val", "var", "when", "while",
			]
		case "c", "cc", "cpp", "cxx", "h", "hpp", "m", "mm":
			keywords = [
				"auto", "break", "case", "char", "class", "const", "continue", "default", "do",
				"double", "else", "enum", "extern", "false", "float", "for", "if", "int",
				"long", "namespace", "new", "nullptr", "private", "protected", "public",
				"return", "short", "signed", "sizeof", "static", "struct", "switch", "template",
				"this", "throw", "true", "try", "typedef", "union", "unsigned", "virtual", "void",
				"volatile", "while",
			]
		case "go", "rs":
			keywords = [
				"as", "break", "case", "const", "continue", "crate", "defer", "else", "enum",
				"false", "fn", "for", "func", "go", "if", "impl", "import", "in", "interface",
				"let", "loop", "map", "match", "mod", "move", "mut", "package", "pub", "range",
				"return", "select", "self", "struct", "super", "switch", "trait", "true", "type",
				"var", "where", "while",
			]
		default:
			keywords = []
		}
		guard !keywords.isEmpty else { return }
		let pattern = "\\b(?:\(keywords.joined(separator: "|")))\\b"
		applyMatches(pattern: pattern, source: source, to: &result, foregroundColor: .purple)
	}

	private static func applyLiteralHighlighting(
		to result: inout AttributedString,
		source: String
	) {
		applyMatches(
			pattern: "\\b(?:0x[0-9A-Fa-f]+|[0-9]+(?:\\.[0-9]+)?)\\b",
			source: source,
			to: &result,
			foregroundColor: .blue
		)
		applyMatches(
			pattern: "(?:\\\"(?:\\\\.|[^\\\"])*\\\"|'(?:\\\\.|[^'])*')",
			source: source,
			to: &result,
			foregroundColor: .red
		)
	}

	private static func applyCommentHighlighting(
		to result: inout AttributedString,
		source: String,
		filePath: String?
	) {
		let fileExtension = filePath.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
		let prefix: String
		if ["py", "rb", "sh", "zsh", "yaml", "yml"].contains(fileExtension) {
			prefix = "#"
		} else if fileExtension == "sql" {
			prefix = "--"
		} else {
			prefix = "//"
		}
		guard let commentIndex = commentIndex(in: source, prefix: prefix) else { return }
		let location = source.distance(from: source.startIndex, to: commentIndex)
		apply(
			DiffTextRange(location: location, length: source.count - location),
			to: &result,
			foregroundColor: .secondary
		)
	}

	private static func commentIndex(in source: String, prefix: String) -> String.Index? {
		var quote: Character?
		var isEscaped = false
		var index = source.startIndex
		while index < source.endIndex {
			let character = source[index]
			if isEscaped {
				isEscaped = false
			} else if quote != nil, character == "\\" {
				isEscaped = true
			} else if let currentQuote = quote {
				if character == currentQuote {
					quote = nil
				}
			} else if character == "\"" || character == "'" {
				quote = character
			} else if source[index...].hasPrefix(prefix) {
				return index
			}
			index = source.index(after: index)
		}
		return nil
	}

	private static func applySearchHighlighting(
		to result: inout AttributedString,
		source: String,
		searchText: String
	) {
		guard !searchText.isEmpty else { return }
		var searchRange = source.startIndex..<source.endIndex
		while let match = source.range(
			of: searchText,
			options: [.caseInsensitive, .diacriticInsensitive],
			range: searchRange
		) {
			let location = source.distance(from: source.startIndex, to: match.lowerBound)
			let length = source.distance(from: match.lowerBound, to: match.upperBound)
			apply(
				DiffTextRange(location: location, length: length),
				to: &result,
				backgroundColor: Color.yellow.opacity(0.35)
			)
			guard match.upperBound < source.endIndex else { break }
			searchRange = match.upperBound..<source.endIndex
		}
	}

	private static func applyMatches(
		pattern: String,
		source: String,
		to result: inout AttributedString,
		foregroundColor: Color
	) {
		guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
		let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
		for match in expression.matches(in: source, range: fullRange) {
			guard let range = Range(match.range, in: source) else { continue }
			apply(
				DiffTextRange(
					location: source.distance(from: source.startIndex, to: range.lowerBound),
					length: source.distance(from: range.lowerBound, to: range.upperBound)
				),
				to: &result,
				foregroundColor: foregroundColor
			)
		}
	}

	private static func apply(
		_ range: DiffTextRange,
		to result: inout AttributedString,
		foregroundColor: Color? = nil,
		backgroundColor: Color? = nil
	) {
		guard range.location >= 0, range.length > 0,
			range.location + range.length <= result.characters.count
		else { return }
		let lowerBound = result.characters.index(result.startIndex, offsetBy: range.location)
		let upperBound = result.characters.index(lowerBound, offsetBy: range.length)
		if let foregroundColor {
			result[lowerBound..<upperBound].foregroundColor = foregroundColor
		}
		if let backgroundColor {
			result[lowerBound..<upperBound].backgroundColor = backgroundColor
		}
	}
}
