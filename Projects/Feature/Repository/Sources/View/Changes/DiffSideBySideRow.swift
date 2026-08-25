import Foundation

struct DiffSideBySideRow: Identifiable, Equatable, Sendable {
	let id: Int
	let fullWidthLine: DiffLine?
	let oldLine: DiffLine?
	let newLine: DiffLine?

	var searchableText: String {
		if let fullWidthLine {
			return fullWidthLine.sourceText
		}
		return [oldLine?.sourceText, newLine?.sourceText]
			.compactMap { $0 }
			.joined(separator: "\n")
	}

	var actionLine: DiffLine? {
		if oldLine?.showsAction == true {
			return oldLine
		}
		if newLine?.showsAction == true {
			return newLine
		}
		return nil
	}
}
