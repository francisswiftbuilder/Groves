import SwiftUI

struct CommitGraphRow: View, Equatable {
	let item: CommitGraphItem
	let isSelected: Bool

	nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.item == rhs.item && lhs.isSelected == rhs.isSelected
	}

	var body: some View {
		HStack(spacing: CommitGraphMetrics.contentSpacing) {
			CommitGraphLaneView(item: item, isSelected: isSelected)
				.frame(width: laneWidth, height: CommitGraphMetrics.rowHeight)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					Text(item.commit.subject)
						.font(.subheadline.weight(.medium))
						.lineLimit(1)
						.layoutPriority(1)

					if let reference = item.commit.references.first {
						CommitGraphReference(reference: reference)
					}

					if item.commit.references.count > 1 {
						CommitGraphReferenceOverflow(count: item.commit.references.count - 1)
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
		}
		.frame(maxWidth: .infinity, minHeight: CommitGraphMetrics.rowHeight, alignment: .leading)
		.padding(.trailing, 12)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private var laneWidth: CGFloat {
		CommitGraphMetrics.width(for: item.visibleLaneCount)
	}
}
