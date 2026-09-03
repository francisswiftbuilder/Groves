import SwiftUI

struct CommitGraphRow: View, Equatable {
	let item: CommitGraphItem
	let isSelected: Bool
	let remoteNames: Set<String>

	nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.item == rhs.item
			&& lhs.isSelected == rhs.isSelected
			&& lhs.remoteNames == rhs.remoteNames
	}

	var body: some View {
		HStack(spacing: CommitGraphMetrics.contentSpacing) {
			CommitGraphLaneView(item: item, isSelected: isSelected)
				.frame(width: laneWidth)
				.frame(minHeight: CommitGraphMetrics.rowHeight, maxHeight: .infinity)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				Text(item.commit.subject)
					.font(.subheadline.weight(.medium))
					.lineLimit(1)

				if !references.isEmpty {
					FlowLayout(spacing: 5) {
						ForEach(references) { reference in
							CommitGraphReference(descriptor: reference)
						}
					}
				}

				HStack(spacing: 6) {
					Text(item.commit.author)
						.lineLimit(1)
					Text("·")
						.accessibilityHidden(true)
					Text(item.commit.date.formatted(date: .abbreviated, time: .shortened))
						.lineLimit(1)
						.monospacedDigit()
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.vertical, 5)
		}
		.frame(maxWidth: .infinity, minHeight: CommitGraphMetrics.rowHeight, alignment: .leading)
		.padding(.trailing, 10)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private var laneWidth: CGFloat {
		CommitGraphMetrics.width(for: item.visibleLaneCount)
	}

	private var references: [CommitGraphReferenceDescriptor] {
		CommitGraphReferenceDescriptor.descriptors(
			for: item.commit.references,
			remoteNames: remoteNames
		)
	}
}
