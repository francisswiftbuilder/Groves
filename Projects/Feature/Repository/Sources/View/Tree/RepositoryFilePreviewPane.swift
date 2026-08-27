import AppKit
import DomainGitInterface
import FeatureRepositoryUI
import Foundation
import SwiftUI

struct RepositoryFilePreviewPane: View {
	let node: RepositoryTreeNode?
	let preview: RepositoryFilePreview

	var body: some View {
		previewContent
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.safeAreaInset(edge: .top, spacing: 0) {
				RepositoryFilePreviewHeader(node: node, byteCount: preview.byteCount)
			}
	}

	@ViewBuilder
	private var previewContent: some View {
		if let node {
			if node.isDirectory {
				EmptyStateView(
					title: node.name,
					message: "\(node.children.count) items",
					systemImage: "folder"
				)
			} else {
				switch preview {
				case .none:
					EmptyStateView(
						title: "No Preview",
						message: "Select the file again to load its preview.",
						systemImage: "doc.text.magnifyingglass"
					)
				case .loading:
					LoadingStateView(
						title: "Loading Preview",
						message: "Reading the selected file."
					)
				case .text(let content, _):
					RepositoryTextPreview(content: content)
				case .image(let data):
					RepositoryImagePreview(data: data)
				case .unsupported(let byteCount):
					EmptyStateView(
						title: "Preview Unavailable",
						message: ByteCountFormatter.string(
							fromByteCount: Int64(byteCount),
							countStyle: .file
						),
						systemImage: "doc.questionmark"
					)
				case .failure(let message):
					EmptyStateView(
						title: "Unable to Load Preview",
						message: message,
						systemImage: "exclamationmark.triangle"
					)
				}
			}
		} else {
			EmptyStateView(
				title: "No File Selected",
				message: "Select a file in the tree to preview it.",
				systemImage: "doc.text.magnifyingglass"
			)
		}
	}
}
