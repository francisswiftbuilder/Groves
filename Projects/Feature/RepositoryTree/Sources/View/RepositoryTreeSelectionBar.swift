import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeSelectionBar: View {
	let node: RepositoryTreeNode

	var body: some View {
		HStack(spacing: 7) {
			Image(systemName: node.isDirectory ? "folder" : "doc")
				.symbolRenderingMode(.hierarchical)
				.accessibilityHidden(true)
			Text(node.path)
				.lineLimit(1)
				.truncationMode(.middle)
			Spacer()
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 12)
		.padding(.vertical, 7)
		.background(.bar)
		.accessibilityElement(children: .combine)
	}
}
