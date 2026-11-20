import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeSelectionBar: View {
	let node: RepositoryTreeNode?

	var body: some View {
		HStack(spacing: 7) {
			if let node {
				Image(systemName: node.isDirectory ? "folder" : "doc")
					.symbolRenderingMode(.hierarchical)
					.accessibilityHidden(true)
				Text(node.path)
					.lineLimit(1)
					.truncationMode(.middle)
			}
			Spacer()
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 12)
		.frame(height: 30)
		.background(.bar)
		.accessibilityElement(children: .combine)
	}
}
