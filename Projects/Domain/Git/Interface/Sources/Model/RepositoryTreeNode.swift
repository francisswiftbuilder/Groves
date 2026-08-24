import Foundation

public struct RepositoryTreeNode: Identifiable, Hashable, Sendable {
	public let name: String
	public let path: String
	public let children: [RepositoryTreeNode]

	public var id: String { path }
	public var isDirectory: Bool { !children.isEmpty }

	public init(name: String, path: String, children: [RepositoryTreeNode]) {
		self.name = name
		self.path = path
		self.children = children
	}
}
