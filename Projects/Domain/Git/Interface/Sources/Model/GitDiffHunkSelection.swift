import Foundation

public struct GitDiffHunkSelection: Hashable, Sendable {
	public let oldStartLine: Int
	public let newStartLine: Int

	public init(oldStartLine: Int, newStartLine: Int) {
		self.oldStartLine = oldStartLine
		self.newStartLine = newStartLine
	}
}
