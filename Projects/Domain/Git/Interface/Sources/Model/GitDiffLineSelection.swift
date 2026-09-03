import Foundation

public struct GitDiffLineSelection: Hashable, Sendable {
	public let oldLineNumber: Int?
	public let newLineNumber: Int?

	public init(oldLineNumber: Int?, newLineNumber: Int?) {
		self.oldLineNumber = oldLineNumber
		self.newLineNumber = newLineNumber
	}
}
