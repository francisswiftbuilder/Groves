import Foundation

public struct RepositoryOperationState: Hashable, Sendable {
	public let head: RepositoryHeadState
	public let operation: RepositoryOperation?
	public let conflicts: [GitConflict]

	public init(
		head: RepositoryHeadState,
		operation: RepositoryOperation? = nil,
		conflicts: [GitConflict] = []
	) {
		self.head = head
		self.operation = operation
		self.conflicts = conflicts
	}

	public var isIdle: Bool {
		operation == nil && conflicts.isEmpty
	}

	public var isDetached: Bool {
		head == .detached
	}

	public var hasConflicts: Bool {
		!conflicts.isEmpty
	}

	public static let normal = RepositoryOperationState(head: .attached)
	public static let detachedHead = RepositoryOperationState(head: .detached)
	public static let mergeInProgress = RepositoryOperationState(
		head: .attached,
		operation: RepositoryOperation(kind: .merge)
	)
	public static let rebaseInProgress = RepositoryOperationState(
		head: .detached,
		operation: RepositoryOperation(kind: .rebase)
	)
	public static let cherryPickInProgress = RepositoryOperationState(
		head: .attached,
		operation: RepositoryOperation(kind: .cherryPick)
	)
	public static let revertInProgress = RepositoryOperationState(
		head: .attached,
		operation: RepositoryOperation(kind: .revert)
	)
	public static let conflicted = RepositoryOperationState(
		head: .attached,
		conflicts: [
			GitConflict(
				path: "",
				kind: .bothModified,
				hasBase: true,
				hasOurs: true,
				hasTheirs: true
			)
		]
	)
}
