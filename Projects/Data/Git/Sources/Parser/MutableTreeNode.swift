import DomainGitInterface
import Foundation

struct MutableTreeNode {
	let name: String
	let path: String
	var children: [String: MutableTreeNode] = [:]

	mutating func insert(components: ArraySlice<String>, parentPath: String) {
		guard let name = components.first else { return }
		let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
		var child = children[name] ?? MutableTreeNode(name: name, path: path)
		child.insert(components: components.dropFirst(), parentPath: path)
		children[name] = child
	}
}
