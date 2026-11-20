import CoreRepositoryUI
import SwiftUI

public struct RepositoryTreeView: View {
	private let viewModel: RepositoryTreeViewModel

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
					RepositoryTreeList(viewModel: viewModel)
						.frame(minWidth: 220, idealWidth: 340, maxWidth: 520)

					RepositoryFilePreviewPane(viewModel: viewModel)
						.frame(minWidth: 260, idealWidth: 620, maxWidth: .infinity)
				}
			}
		}
	}
}
