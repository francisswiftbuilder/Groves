import Foundation

public struct GitAmendChange: Identifiable, Hashable, Sendable {
	public let path: String
	public let previousPath: String?
	public let state: GitFileState

	public var id: String { path }

	public init(path: String, previousPath: String?, state: GitFileState) {
		self.path = path
		self.previousPath = previousPath
		self.state = state
	}
}
