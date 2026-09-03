import Foundation

public enum GitConflictHunkResolution: Hashable, Sendable {
	case current
	case incoming
	case both
}
