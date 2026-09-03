import DomainGitInterface
import Foundation

extension RepositoryTreeNode {
	init(_ node: MutableTreeNode) {
		let children = node.children.values
			.map(RepositoryTreeNode.init)
			.sorted {
				if $0.isDirectory != $1.isDirectory {
					return $0.isDirectory
				}
				return $0.name.localizedStandardCompare($1.name) == .orderedAscending
			}
		self.init(name: node.name, path: node.path, children: children)
	}
}
