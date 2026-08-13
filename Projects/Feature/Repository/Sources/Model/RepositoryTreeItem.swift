import DomainGitInterface

struct RepositoryTreeItem: Identifiable, Hashable, Sendable {
	let node: RepositoryTreeNode
	let depth: Int
	let ancestorHasFollowingSibling: [Bool]
	let isLastSibling: Bool

	var id: String { node.id }
}
