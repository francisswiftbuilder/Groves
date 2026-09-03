import Foundation

public enum GitDiffHunkAction: Equatable, Sendable {
	case stage
	case unstage
	case discard
}
