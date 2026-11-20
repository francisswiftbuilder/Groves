import AppKit
import CoreRepositoryUI
import DomainGitInterface
import Foundation
import SwiftUI

public struct RepositoryTreeView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	private let viewModel: RepositoryTreeViewModel
	@FocusState private var isTreeFocused: Bool

	public init(viewModel: RepositoryTreeViewModel) {
		self.viewModel = viewModel
	}

	public var body: some View {
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

					RepositoryFilePreviewPane(viewModel: viewModel)
						.frame(minWidth: 260, idealWidth: 620, maxWidth: .infinity)
				}
			}
		}
	}

	private var treePane: some View {
		List(viewModel.visibleTreeItems, selection: selectedTreeNodeBinding) { item in
			RepositoryTreeRow(
				item: item,
				isExpanded: viewModel.expandedTreeNodeIDs.contains(item.id),
				onToggleExpansion: {
					viewModel.setTreeNode(
						item.id,
						isExpanded: !viewModel.expandedTreeNodeIDs.contains(item.id)
					)
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
			RepositoryTreeHeader(fileCount: viewModel.fileCount)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			RepositoryTreeSelectionBar(node: viewModel.selectedTreeItem?.node)
		}
		.task {
			await Task.yield()
			isTreeFocused = true
		}
	}

	private var selectedTreeNodeBinding: Binding<String?> {
		Binding(
			get: { viewModel.selectedTreeNodeID },
			set: { nodeID in viewModel.didSelectTreeNode(id: nodeID) }
		)
	}

	private var treeAnimation: Animation {
		reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
	}

	private func expandSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem = viewModel.selectedTreeItem,
			selectedItem.node.isDirectory,
			!viewModel.expandedTreeNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				viewModel.setTreeNode(selectedNodeID, isExpanded: true)
			}
		}
		return .handled
	}

	private func collapseSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem = viewModel.selectedTreeItem,
			selectedItem.node.isDirectory,
			viewModel.expandedTreeNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				viewModel.setTreeNode(selectedNodeID, isExpanded: false)
			}
		}
		return .handled
	}
}
