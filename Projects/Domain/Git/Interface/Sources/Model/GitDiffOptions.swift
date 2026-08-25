import Foundation

public struct GitDiffOptions: Hashable, Sendable {
	public var contextLineCount: Int?
	public var ignoresWhitespace: Bool

	public init(contextLineCount: Int? = 3, ignoresWhitespace: Bool = false) {
		self.contextLineCount = contextLineCount
		self.ignoresWhitespace = ignoresWhitespace
	}
}
