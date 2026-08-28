import AppKit
import SwiftUI

public final class ProportionalSplitView: NSSplitView {
	var proportions: [CGFloat] = [1, 1, 1]
	var minimumWidths: [CGFloat] = [180, 260, 200]
	private var didApplyInitialDistribution = false

	public override func layout() {
		super.layout()
		applyInitialDistributionIfNeeded()
	}

	func minimumPosition(ofDividerAt dividerIndex: Int) -> CGFloat {
		let widths = effectiveMinimumWidths
		let precedingWidths = widths.prefix(dividerIndex + 1).reduce(0, +)
		return precedingWidths + dividerThickness * CGFloat(dividerIndex)
	}

	func maximumPosition(ofDividerAt dividerIndex: Int) -> CGFloat {
		let widths = effectiveMinimumWidths
		let followingWidths = widths.suffix(from: dividerIndex + 1).reduce(0, +)
		let followingDividers = max(subviews.count - dividerIndex - 2, 0)
		return bounds.width - followingWidths - dividerThickness * CGFloat(followingDividers)
	}

	private var effectiveMinimumWidths: [CGFloat] {
		let availableWidth = max(
			bounds.width - dividerThickness * CGFloat(max(subviews.count - 1, 0)),
			0
		)
		let minimumWidth = minimumWidths.reduce(0, +)
		guard minimumWidth > 0, minimumWidth > availableWidth else { return minimumWidths }
		let scale = availableWidth / minimumWidth
		return minimumWidths.map { $0 * scale }
	}

	private func applyInitialDistributionIfNeeded() {
		guard
			!didApplyInitialDistribution,
			subviews.count == 3,
			window != nil,
			bounds.width >= 480
		else {
			return
		}

		let totalProportion = proportions.reduce(0, +)
		guard totalProportion > 0 else { return }

		let availableWidth = bounds.width - dividerThickness * 2
		didApplyInitialDistribution = true

		var position: CGFloat = 0
		for dividerIndex in 0..<2 {
			position += availableWidth * proportions[dividerIndex] / totalProportion
			setPosition(position, ofDividerAt: dividerIndex)
			position += dividerThickness
		}
	}
}
