import DomainGitInterface
import SwiftUI

struct FlowLayout: Layout {
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
