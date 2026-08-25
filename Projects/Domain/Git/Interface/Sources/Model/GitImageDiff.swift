import Foundation

public struct GitImageDiff: Hashable, Sendable {
	public let before: Data?
	public let after: Data?

	public init(before: Data?, after: Data?) {
		self.before = before
		self.after = after
	}
}
