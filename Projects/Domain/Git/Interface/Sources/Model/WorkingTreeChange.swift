import Foundation

public struct WorkingTreeChange: Identifiable, Hashable, Sendable {
	public let path: String
	public let previousPath: String?
	public let indexState: GitFileState
	public let workingTreeState: GitFileState

	public var id: String { path }
	public var isStaged: Bool { indexState != .unchanged && indexState != .untracked }
	public var hasWorkingTreeChange: Bool { workingTreeState != .unchanged }

	public var displayState: GitFileState {
		hasWorkingTreeChange ? workingTreeState : indexState
	}

	public init(
		path: String,
		previousPath: String?,
		indexState: GitFileState,
		workingTreeState: GitFileState
	) {
		self.path = path
		self.previousPath = previousPath
		self.indexState = indexState
		self.workingTreeState = workingTreeState
	}
}
