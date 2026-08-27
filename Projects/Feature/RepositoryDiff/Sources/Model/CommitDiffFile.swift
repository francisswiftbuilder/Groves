import Foundation

public struct CommitDiffFile: Identifiable, Hashable, Sendable {
	public let id: String
	public let path: String
	public let previousPath: String?
	public let diff: String
	public let additions: Int
	public let deletions: Int

	public var fileName: String {
		URL(fileURLWithPath: path).lastPathComponent
	}
}
