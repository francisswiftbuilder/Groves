import SwiftUI

enum CommitGraphMetrics {
	static let leadingInset: CGFloat = 10
	static let laneWidth: CGFloat = 16
	static let trailingInset: CGFloat = 4
	static let contentSpacing: CGFloat = 10
	static let rowHeight: CGFloat = 52

	static func width(for laneCapacity: Int) -> CGFloat {
		leadingInset + CGFloat(laneCapacity) * laneWidth + trailingInset
	}
}
