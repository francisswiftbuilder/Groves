import DomainGitInterface
import Foundation
import Observation

@MainActor
@Observable
public final class RepositoryTreeViewModel {
	public struct Dependencies {
		public let contentUseCase: any RepositoryContentUseCase

		public init(contentUseCase: any RepositoryContentUseCase) {
			self.contentUseCase = contentUseCase
		}
	}

	private(set) var fileTree: [RepositoryTreeNode] = []
	private(set) var visibleTreeItems: [RepositoryTreeItem] = []
	private(set) var fileCount = 0
	private(set) var selectedTreeNodeID: String?
	private(set) var expandedTreeNodeIDs: Set<String> = []
	private(set) var filePreview: RepositoryFilePreview = .none

	private let dependencies: Dependencies
	private var repositoryURL: URL?
	@ObservationIgnored private var visibleTreeIndices: [String: Int] = [:]
	@ObservationIgnored private var filePreviewTask: Task<Void, Never>?

	public init(dependencies: Dependencies) {
		self.dependencies = dependencies
	}

	deinit {
		filePreviewTask?.cancel()
	}

	var selectedTreeItem: RepositoryTreeItem? {
		guard let selectedTreeNodeID, let index = visibleTreeIndices[selectedTreeNodeID] else {
			return nil
		}
		return visibleTreeItems[index]
	}

	public func apply(_ snapshot: RepositorySnapshot, repositoryURL: URL?) {
		let preservesCurrentPreview = self.repositoryURL == repositoryURL
		self.repositoryURL = repositoryURL
		if fileTree != snapshot.fileTree {
			fileTree = snapshot.fileTree
			fileCount = RepositoryTreeLayoutBuilder.statistics(in: fileTree).files
			updateVisibleTreeItems()
		}
		guard selectedTreeNodeID != nil else { return }
		if selectedTreeItem == nil {
			didSelectTreeNode(id: nil)
		} else {
			loadSelectedPreview(preservesCurrentPreview: preservesCurrentPreview)
		}
	}

	public func reset() {
		filePreviewTask?.cancel()
		filePreviewTask = nil
		repositoryURL = nil
		fileTree = []
		visibleTreeItems = []
		visibleTreeIndices = [:]
		fileCount = 0
		selectedTreeNodeID = nil
		expandedTreeNodeIDs = []
		filePreview = .none
	}

	public func onAppear() {
		guard selectedTreeNodeID != nil, filePreview == .none else { return }
		loadSelectedPreview(preservesCurrentPreview: false)
	}

	public func onDisappear() {
		filePreviewTask?.cancel()
		filePreviewTask = nil
		if filePreview == .loading {
			filePreview = .none
		}
	}

	func setTreeNode(_ nodeID: String, isExpanded: Bool) {
		guard expandedTreeNodeIDs.contains(nodeID) != isExpanded else { return }
		if isExpanded {
			expandedTreeNodeIDs.insert(nodeID)
		} else {
			expandedTreeNodeIDs.remove(nodeID)
		}
		updateVisibleTreeItems()
		if selectedTreeNodeID != nil, selectedTreeItem == nil {
			didSelectTreeNode(id: nil)
		}
	}

	func didSelectTreeNode(id: String?) {
		let visibleID = id.flatMap { visibleTreeIndices[$0] == nil ? nil : $0 }
		guard selectedTreeNodeID != visibleID else { return }
		selectedTreeNodeID = visibleID
		loadSelectedPreview(preservesCurrentPreview: false)
	}

	private func updateVisibleTreeItems() {
		let items = RepositoryTreeLayoutBuilder.build(
			nodes: fileTree, expandedNodeIDs: expandedTreeNodeIDs)
		visibleTreeIndices = Dictionary(
			items.enumerated().map { ($0.element.id, $0.offset) },
			uniquingKeysWith: { first, _ in first })
		visibleTreeItems = items
	}

	private func loadSelectedPreview(preservesCurrentPreview: Bool) {
		filePreviewTask?.cancel()
		filePreviewTask = nil
		guard let node = selectedTreeItem?.node, !node.isDirectory, let repositoryURL else {
			filePreview = .none
			return
		}

		if !preservesCurrentPreview || filePreview == .none, filePreview != .loading {
			filePreview = .loading
		}
		let contentUseCase = dependencies.contentUseCase
		filePreviewTask = Task { [weak self] in
			let preview: RepositoryFilePreview
			do {
				try await Task.sleep(for: .milliseconds(150))
				preview = try await Self.loadPreview(
					at: node.path, in: repositoryURL, using: contentUseCase)
			} catch is CancellationError {
				return
			} catch {
				preview = .failure(error.localizedDescription)
			}
			guard let self, !Task.isCancelled, self.repositoryURL == repositoryURL,
				selectedTreeNodeID == node.id
			else { return }
			filePreview = preview
		}
	}

	@concurrent
	private static func loadPreview(
		at path: String, in repositoryURL: URL, using contentUseCase: any RepositoryContentUseCase
	) async throws -> RepositoryFilePreview {
		try Task.checkCancellation()
		let data = try await contentUseCase.loadFileContents(at: path, in: repositoryURL)
		try Task.checkCancellation()
		return RepositoryFilePreview.make(path: path, data: data)
	}
}
