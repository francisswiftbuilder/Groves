import DomainGitInterface
import SwiftUI

struct CommitInspectorView: View {
	let commit: GitCommit?
	let files: [CommitDiffFile]
	@Binding var selectedFileID: CommitDiffFile.ID?

	var body: some View {
		VStack(spacing: 0) {
			inspectorHeader
			Divider()
			inspectorContent
		}
	}

	private var inspectorHeader: some View {
		HStack {
			Text("Commit")
				.font(.subheadline.weight(.semibold))
			Spacer()
			if let commit {
				ShareLink(item: commit.hash) {
					Image(systemName: "square.and.arrow.up")
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.plain)
				.help("Share Commit Hash")
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}

	@ViewBuilder
	private var inspectorContent: some View {
		if let commit {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					commitSummary(commit)
						.padding(16)

					Divider()

					commitInformation(commit)
						.padding(16)

					if !commit.references.isEmpty {
						Divider()
					}

					commitReferences(commit)
						.padding(.horizontal, 16)
						.padding(.vertical, commit.references.isEmpty ? 0 : 16)

					Divider()

					changedFiles
						.padding(16)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		} else {
			EmptyStateView(
				title: "No Commit Selected",
				message: "Select a commit to inspect its details.",
				systemImage: "clock"
			)
		}
	}

	private func commitSummary(_ commit: GitCommit) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(commit.subject)
				.font(.headline)
				.fixedSize(horizontal: false, vertical: true)
			if !commit.body.isEmpty {
				Text(commit.body)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
	}

	private func commitInformation(_ commit: GitCommit) -> some View {
		CommitInspectorSection("Information") {
			CommitInspectorValue("Author", value: commit.author)
			CommitInspectorValue(
				"Committed",
				value: commit.date.formatted(date: .abbreviated, time: .shortened)
			)
			CommitInspectorValue("Hash", value: commit.shortHash, isMonospaced: true)
			if !commit.parentHashes.isEmpty {
				CommitInspectorValue(
					"Parents",
					value: commit.parentHashes.map { String($0.prefix(7)) }.joined(separator: ", "),
					isMonospaced: true
				)
			}
		}
	}

	@ViewBuilder
	private func commitReferences(_ commit: GitCommit) -> some View {
		if !commit.references.isEmpty {
			CommitInspectorSection("Branches") {
				FlowLayout(spacing: 6) {
					ForEach(commit.references, id: \.self) { reference in
						CommitReferenceTag(reference: reference)
					}
				}
			}
		}
	}

	private var changedFiles: some View {
		CommitInspectorSection("Files") {
			VStack(spacing: 4) {
				ForEach(files) { file in
					Button {
						selectedFileID = file.id
					} label: {
						CommitChangedFileRow(
							file: file,
							isSelected: file.id == selectedFileID
						)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}
}

private struct CommitInspectorSection<Content: View>: View {
	let title: String
	@ViewBuilder let content: () -> Content

	init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
		self.title = title
		self.content = content
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.subheadline.weight(.semibold))
			content()
		}
	}
}

private struct CommitInspectorValue: View {
	let title: String
	let value: String
	let isMonospaced: Bool

	init(_ title: String, value: String, isMonospaced: Bool = false) {
		self.title = title
		self.value = value
		self.isMonospaced = isMonospaced
	}

	var body: some View {
		LabeledContent(title) {
			Text(value)
				.font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
				.multilineTextAlignment(.trailing)
				.textSelection(.enabled)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}
}

private struct CommitReferenceTag: View {
	let reference: String

	var body: some View {
		Text(reference)
			.font(.caption.weight(.medium))
			.foregroundStyle(referenceColor)
			.padding(.horizontal, 7)
			.padding(.vertical, 4)
			.background(referenceColor.opacity(0.12), in: Capsule())
	}

	private var referenceColor: Color {
		if reference.contains("HEAD") {
			return .primary
		}
		return reference.hasPrefix("origin/") ? .secondary : .blue
	}
}

private struct CommitChangedFileRow: View {
	let file: CommitDiffFile
	let isSelected: Bool

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "doc")
				.foregroundStyle(.secondary)
				.frame(width: 14)
			Text(file.path)
				.font(.caption)
				.multilineTextAlignment(.leading)
				.lineLimit(2)
			Spacer(minLength: 6)
			Text("+\(file.additions)")
				.foregroundStyle(.green)
			Text("−\(file.deletions)")
				.foregroundStyle(.red)
		}
		.font(.caption.monospacedDigit())
		.padding(.horizontal, 6)
		.padding(.vertical, 5)
		.background(
			isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6)
		)
		.contentShape(.rect)
	}
}

private struct FlowLayout: Layout {
	let spacing: CGFloat

	func sizeThatFits(
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) -> CGSize {
		let width = proposal.width ?? .infinity
		let positions = positions(for: subviews, width: width)
		let height = positions.map(\.maxY).max() ?? 0
		return CGSize(width: proposal.width ?? positions.map(\.maxX).max() ?? 0, height: height)
	}

	func placeSubviews(
		in bounds: CGRect,
		proposal: ProposedViewSize,
		subviews: Subviews,
		cache: inout ()
	) {
		let positions = positions(for: subviews, width: bounds.width)
		for (index, subview) in subviews.enumerated() {
			subview.place(
				at: CGPoint(x: bounds.minX + positions[index].minX, y: bounds.minY + positions[index].minY),
				proposal: .unspecified
			)
		}
	}

	private func positions(for subviews: Subviews, width: CGFloat) -> [CGRect] {
		var positions: [CGRect] = []
		var origin = CGPoint.zero
		var rowHeight: CGFloat = 0

		for subview in subviews {
			let size = subview.sizeThatFits(.unspecified)
			if origin.x > 0, origin.x + size.width > width {
				origin.x = 0
				origin.y += rowHeight + spacing
				rowHeight = 0
			}
			positions.append(CGRect(origin: origin, size: size))
			origin.x += size.width + spacing
			rowHeight = max(rowHeight, size.height)
		}

		return positions
	}
}
