import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var expandedNodeIDs: Set<String> = []
	@State private var selectedNodeID: String?
	@FocusState private var isTreeFocused: Bool

	var body: some View {
		Group {
			if viewModel.fileTree.isEmpty {
				EmptyStateView(
					title: "Empty Repository",
					message: "Tracked files will appear here.",
					systemImage: "folder"
				)
			} else {
				HSplitView {
					treePane
						.frame(minWidth: 220, idealWidth: 340, maxWidth: 520)

					RepositoryFilePreviewPane(
						node: selectedItem?.node,
						preview: viewModel.filePreview
					)
					.frame(minWidth: 260, idealWidth: 620, maxWidth: .infinity)
				}
			}
		}
		.navigationTitle("Tree")
		.navigationSubtitle("Repository files")
		.onChange(of: viewModel.repositoryURL) {
			expandedNodeIDs = []
			selectedNodeID = nil
		}
	}

	private var treePane: some View {
		List(visibleItems, selection: $selectedNodeID) { item in
			RepositoryTreeRow(
				item: item,
				expandedNodeIDs: $expandedNodeIDs,
				onSelect: {
					selectedNodeID = item.id
					isTreeFocused = true
				}
			)
			.tag(item.id)
			.listRowSeparator(.hidden)
			.listRowInsets(
				EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 10)
			)
		}
		.listStyle(.inset)
		.focused($isTreeFocused)
		.onKeyPress(.rightArrow, action: expandSelectedNode)
		.onKeyPress(.leftArrow, action: collapseSelectedNode)
		.safeAreaInset(edge: .top, spacing: 0) {
			RepositoryTreeHeader(statistics: statistics)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			if let selectedItem {
				RepositoryTreeSelectionBar(node: selectedItem.node)
			}
		}
		.task(id: selectedNodeID) {
			try? await Task.sleep(for: .milliseconds(1))
			guard !Task.isCancelled else { return }
			viewModel.didSelectTreeNode(selectedItem?.node)
		}
		.task {
			await Task.yield()
			isTreeFocused = true
		}
	}

	private var visibleItems: [RepositoryTreeItem] {
		RepositoryTreeLayoutBuilder.build(
			nodes: viewModel.fileTree,
			expandedNodeIDs: expandedNodeIDs
		)
	}

	private var statistics: (directories: Int, files: Int) {
		RepositoryTreeLayoutBuilder.statistics(in: viewModel.fileTree)
	}

	private var selectedItem: RepositoryTreeItem? {
		visibleItems.first { $0.id == selectedNodeID }
	}

	private var treeAnimation: Animation {
		reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
	}

	private func expandSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem,
			selectedItem.node.isDirectory,
			!expandedNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				expandedNodeIDs.formUnion([selectedNodeID])
			}
		}
		return .handled
	}

	private func collapseSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem,
			selectedItem.node.isDirectory,
			expandedNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				expandedNodeIDs.subtract([selectedNodeID])
			}
		}
		return .handled
	}
}
