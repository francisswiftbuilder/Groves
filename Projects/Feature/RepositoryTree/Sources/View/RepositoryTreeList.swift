import SwiftUI

struct RepositoryTreeList: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@FocusState private var isTreeFocused: Bool
	let viewModel: RepositoryTreeViewModel

	var body: some View {
		VStack(spacing: 0) {
			List(selection: fileSelection) {
				ForEach(viewModel.visibleTreeItems) { item in
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
					.listRowInsets(.init(top: 1, leading: 8, bottom: 1, trailing: 10))
				}
			}
			.listStyle(.plain)
			.focused($isTreeFocused)
			.onKeyPress(.rightArrow) { setSelectedFolderExpanded(true) }
			.onKeyPress(.leftArrow) { setSelectedFolderExpanded(false) }
		}
		.defaultFocus($isTreeFocused, true)
		.safeAreaInset(edge: .top, spacing: 0) {
			RepositoryTreeHeader(fileCount: viewModel.fileCount)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			RepositoryTreeSelectionBar(viewModel: viewModel)
		}
	}

	private var fileSelection: Binding<String?> {
		Binding(
			get: { viewModel.selectedTreeNodeID },
			set: { viewModel.didSelectTreeNode(id: $0) })
	}

	private func setSelectedFolderExpanded(_ isExpanded: Bool) -> KeyPress.Result {
		guard
			let selectedItem = viewModel.selectedTreeItem,
			selectedItem.node.isDirectory,
			viewModel.expandedTreeNodeIDs.contains(selectedItem.id) != isExpanded
		else { return .ignored }

		let animation: Animation =
			reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
		withAnimation(animation) {
			viewModel.setTreeNode(selectedItem.id, isExpanded: isExpanded)
		}
		return .handled
	}
}
