import FeatureRepositoryDiff
import SwiftUI

struct ConflictCodeSection: View {
	let title: String
	let content: String?
	let filePath: String
	let searchText: String
	let unavailableMessage: String

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 10)
				.frame(height: 28)

			Divider()

			if let content {
				let lines = content.components(separatedBy: "\n")
				ScrollView(.horizontal) {
					VStack(alignment: .leading, spacing: 0) {
						ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
							HStack(spacing: 0) {
								Text(String(index + 1))
									.font(.system(.caption2, design: .monospaced))
									.foregroundStyle(.tertiary)
									.frame(width: 38, alignment: .trailing)
									.padding(.trailing, 8)
									.accessibilityHidden(true)

								Text(
									DiffSyntaxHighlighter.styledText(
										line,
										filePath: filePath,
										kind: .context,
										changedRange: nil,
										searchText: searchText
									)
								)
								.font(.system(size: 12, design: .monospaced))
								.lineLimit(1)
								.fixedSize(horizontal: true, vertical: false)
								.textSelection(.enabled)

								Spacer(minLength: 12)
							}
							.frame(minHeight: 20, alignment: .leading)
							.fixedSize(horizontal: true, vertical: false)
						}
					}
					.padding(.vertical, 6)
					.fixedSize(horizontal: true, vertical: false)
				}
				.defaultScrollAnchor(.leading)
			} else {
				Label(unavailableMessage, systemImage: "doc.slash")
					.font(.callout)
					.foregroundStyle(.secondary)
					.padding(12)
			}
		}
		.background(Color.primary.opacity(0.035))
		.frame(maxWidth: .infinity, alignment: .leading)
		.clipShape(.rect(cornerRadius: 8))
		.overlay {
			RoundedRectangle(cornerRadius: 8)
				.stroke(.separator, lineWidth: 1)
		}
	}
}
