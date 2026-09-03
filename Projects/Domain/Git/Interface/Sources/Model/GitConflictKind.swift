public enum GitConflictKind: String, CaseIterable, Hashable, Sendable {
	case bothDeleted = "DD"
	case addedByUs = "AU"
	case deletedByThem = "UD"
	case addedByThem = "UA"
	case deletedByUs = "DU"
	case bothAdded = "AA"
	case bothModified = "UU"
}
