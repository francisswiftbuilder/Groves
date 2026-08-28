import DomainGitInterface

enum RepositoryTreeLayoutBuilder {
	static func build(
		nodes: [RepositoryTreeNode],
		expandedNodeIDs: Set<String>
	) -> [RepositoryTreeItem] {
		var items: [RepositoryTreeItem] = []
		append(
			nodes: nodes,
			depth: 0,
			ancestorHasFollowingSibling: [],
			expandedNodeIDs: expandedNodeIDs,
			to: &items
		)
		return items
	}

	static func directoryIDs(
		in nodes: [RepositoryTreeNode],
		maximumDepth: Int? = nil
	) -> Set<String> {
		var identifiers: Set<String> = []
		appendDirectoryIDs(
			in: nodes,
			depth: 0,
			maximumDepth: maximumDepth,
			to: &identifiers
		)
		return identifiers
	}

	static func statistics(in nodes: [RepositoryTreeNode]) -> (directories: Int, files: Int) {
		var directoryCount = 0
		var fileCount = 0

		for node in nodes {
			if node.isDirectory {
				directoryCount += 1
				let childStatistics = statistics(in: node.children)
				directoryCount += childStatistics.directories
				fileCount += childStatistics.files
			} else {
				fileCount += 1
			}
		}

		return (directoryCount, fileCount)
	}

	private static func append(
		nodes: [RepositoryTreeNode],
		depth: Int,
		ancestorHasFollowingSibling: [Bool],
		expandedNodeIDs: Set<String>,
		to items: inout [RepositoryTreeItem]
	) {
		for (index, node) in nodes.enumerated() {
			let isLastSibling = index == nodes.count - 1
			items.append(
				RepositoryTreeItem(
					node: node,
					depth: depth,
					ancestorHasFollowingSibling: ancestorHasFollowingSibling,
					isLastSibling: isLastSibling
				)
			)

			guard node.isDirectory, expandedNodeIDs.contains(node.id) else { continue }
			append(
				nodes: node.children,
				depth: depth + 1,
				ancestorHasFollowingSibling: ancestorHasFollowingSibling + [!isLastSibling],
				expandedNodeIDs: expandedNodeIDs,
				to: &items
			)
		}
	}

	private static func appendDirectoryIDs(
		in nodes: [RepositoryTreeNode],
		depth: Int,
		maximumDepth: Int?,
		to identifiers: inout Set<String>
	) {
		guard maximumDepth.map({ depth <= $0 }) ?? true else { return }

		for node in nodes where node.isDirectory {
			identifiers.insert(node.id)
			appendDirectoryIDs(
				in: node.children,
				depth: depth + 1,
				maximumDepth: maximumDepth,
				to: &identifiers
			)
		}
	}
}
