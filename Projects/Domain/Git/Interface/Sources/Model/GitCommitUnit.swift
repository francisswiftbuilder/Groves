import Foundation

public struct GitCommitUnit: Identifiable, Hashable, Sendable {
	public let id: String
	public let path: String
	public let patch: String
	public let hunk: GitDiffHunkSelection?

	public init(id: String, path: String, patch: String, hunk: GitDiffHunkSelection?) {
		self.id = id
		self.path = path
		self.patch = patch
		self.hunk = hunk
	}
}
