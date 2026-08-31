import Combine
import DomainGitInterface
import Foundation

@MainActor
public final class RepositoryTreeViewModel: ObservableObject {
	@Published private(set) var fileTree: [RepositoryTreeNode] = []
	@Published private(set) var selectedTreeNodeID: String?
	@Published var expandedTreeNodeIDs: Set<String> = []
	@Published private(set) var filePreview: RepositoryFilePreview = .none

	private let dependencies: RepositoryTreeViewModelDependencies
	private var repositoryURL: URL?
	private var filePreviewTask: Task<Void, Never>?

	public init(dependencies: RepositoryTreeViewModelDependencies) {
		self.dependencies = dependencies
	}

	private var contentUseCase: any RepositoryContentUseCase {
		dependencies.contentUseCase
	}

	deinit {
		filePreviewTask?.cancel()
	}

	var visibleTreeItems: [RepositoryTreeItem] {
		RepositoryTreeLayoutBuilder.build(
			nodes: fileTree,
			expandedNodeIDs: expandedTreeNodeIDs
		)
	}

	var selectedTreeItem: RepositoryTreeItem? {
		visibleTreeItems.first { $0.id == selectedTreeNodeID }
	}

	public func apply(_ snapshot: RepositorySnapshot, repositoryURL: URL?) {
		self.repositoryURL = repositoryURL
		if fileTree != snapshot.fileTree {
			fileTree = snapshot.fileTree
		}
		guard selectedTreeNodeID != nil else { return }
		didSelectTreeNode(
			node(id: selectedTreeNodeID, in: fileTree),
			preservesCurrentPreview: true
		)
	}

	public func reset() {
		filePreviewTask?.cancel()
		selectedTreeNodeID = nil
		expandedTreeNodeIDs = []
		filePreview = .none
	}

	func setTreeNode(_ nodeID: String, isExpanded: Bool) {
		if isExpanded {
			guard !expandedTreeNodeIDs.contains(nodeID) else { return }
			expandedTreeNodeIDs.insert(nodeID)
		} else {
			guard expandedTreeNodeIDs.contains(nodeID) else { return }
			expandedTreeNodeIDs.remove(nodeID)
		}
	}

	func didSelectTreeNode(id: String?) async {
		await Task.yield()
		guard !Task.isCancelled, selectedTreeNodeID != id else { return }
		didSelectTreeNode(
			node(id: id, in: fileTree),
			preservesCurrentPreview: false
		)
	}

	private func didSelectTreeNode(
		_ node: RepositoryTreeNode?,
		preservesCurrentPreview: Bool
	) {
		if selectedTreeNodeID != node?.id {
			selectedTreeNodeID = node?.id
		}
		filePreviewTask?.cancel()
		if !preservesCurrentPreview {
			filePreview = .none
		}

		guard let node, !node.isDirectory, let repositoryURL else {
			if node == nil || node?.isDirectory == true {
				filePreview = .none
			}
			return
		}

		if !preservesCurrentPreview || filePreview == .none {
			filePreview = .loading
		}
		filePreviewTask = Task {
			do {
				let data = try await contentUseCase.loadFileContents(
					at: node.path,
					in: repositoryURL
				)
				guard !Task.isCancelled, selectedTreeNodeID == node.id else { return }
				filePreview = RepositoryFilePreview.make(path: node.path, data: data)
			} catch is CancellationError {
				return
			} catch {
				guard selectedTreeNodeID == node.id else { return }
				if !preservesCurrentPreview || filePreview == .loading {
					filePreview = .failure(error.localizedDescription)
				}
			}
		}
	}

	private func node(id: String?, in nodes: [RepositoryTreeNode]) -> RepositoryTreeNode? {
		guard let id else { return nil }

		for node in nodes {
			if node.id == id {
				return node
			}
			if let match = self.node(id: id, in: node.children) {
				return match
			}
		}

		return nil
	}
}
