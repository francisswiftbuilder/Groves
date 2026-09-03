public struct GitConflict: Identifiable, Hashable, Sendable {
	public let path: String
	public let kind: GitConflictKind
	public let hasBase: Bool
	public let hasOurs: Bool
	public let hasTheirs: Bool

	public var id: String { path }

	public init(
		path: String,
		kind: GitConflictKind,
		hasBase: Bool,
		hasOurs: Bool,
		hasTheirs: Bool
	) {
		self.path = path
		self.kind = kind
		self.hasBase = hasBase
		self.hasOurs = hasOurs
		self.hasTheirs = hasTheirs
	}
}
