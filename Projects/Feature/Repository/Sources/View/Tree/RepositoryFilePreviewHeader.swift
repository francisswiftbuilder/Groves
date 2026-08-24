import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryFilePreviewHeader: View {
	let node: RepositoryTreeNode?
	let byteCount: Int?

	var body: some View {
		HStack(spacing: 9) {
			Image(systemName: node?.isDirectory == true ? "folder" : "doc.text")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 1) {
				Text(node?.name ?? "Preview")
					.font(.callout.weight(.medium))
					.lineLimit(1)

				if let node {
					Text(node.path)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}

			Spacer(minLength: 12)

			if let byteCount {
				Text(
					ByteCountFormatter.string(
						fromByteCount: Int64(byteCount),
						countStyle: .file
					)
				)
				.font(.caption)
				.foregroundStyle(.secondary)
			}
		}
		.frame(minHeight: 34)
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(.bar)
		.accessibilityElement(children: .combine)
	}
}
