import Foundation

struct DiffDocument: Equatable, Sendable {
	let lines: [DiffLine]

	static let empty = DiffDocument(lines: [])

	var additionCount: Int {
		lines.count { $0.kind == .addition }
	}

	var deletionCount: Int {
		lines.count { $0.kind == .deletion }
	}

	var showsOldLineNumbers: Bool {
		lines.contains { $0.oldLineNumber != nil }
	}

	var showsNewLineNumbers: Bool {
		lines.contains { $0.newLineNumber != nil }
	}
}
