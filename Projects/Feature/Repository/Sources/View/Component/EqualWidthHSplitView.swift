import AppKit
import SwiftUI

struct EqualWidthHSplitView<Leading: View, Center: View, Trailing: View>: NSViewRepresentable {
	private let leading: Leading
	private let center: Center
	private let trailing: Trailing
	private let proportions: [CGFloat]
	private let minimumWidths: [CGFloat]

	init(
		proportions: [CGFloat] = [1, 1, 1],
		minimumWidths: [CGFloat] = [180, 260, 200],
		@ViewBuilder leading: () -> Leading,
		@ViewBuilder center: () -> Center,
		@ViewBuilder trailing: () -> Trailing
	) {
		self.leading = leading()
		self.center = center()
		self.trailing = trailing()
		self.proportions = proportions
		self.minimumWidths = minimumWidths
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	func makeNSView(context: Context) -> ProportionalSplitView {
		let splitView = ProportionalSplitView()
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.proportions = normalizedProportions
		splitView.minimumWidths = normalizedMinimumWidths
		splitView.delegate = context.coordinator

		let leadingView = hostingView(rootView: leading)
		let centerView = hostingView(rootView: center)
		let trailingView = hostingView(rootView: trailing)
		context.coordinator.leadingView = leadingView
		context.coordinator.centerView = centerView
		context.coordinator.trailingView = trailingView

		splitView.addSubview(leadingView)
		splitView.addSubview(centerView)
		splitView.addSubview(trailingView)
		return splitView
	}

	func updateNSView(_ splitView: ProportionalSplitView, context: Context) {
		context.coordinator.leadingView?.rootView = leading
		context.coordinator.centerView?.rootView = center
		context.coordinator.trailingView?.rootView = trailing
		splitView.proportions = normalizedProportions
		splitView.minimumWidths = normalizedMinimumWidths
	}

	private var normalizedProportions: [CGFloat] {
		guard proportions.count == 3, proportions.allSatisfy({ $0 > 0 }) else {
			return [1, 1, 1]
		}
		return proportions
	}

	private var normalizedMinimumWidths: [CGFloat] {
		guard minimumWidths.count == 3, minimumWidths.allSatisfy({ $0 >= 0 }) else {
			return [180, 260, 200]
		}
		return minimumWidths
	}

	private func hostingView<Content: View>(rootView: Content) -> NSHostingView<Content> {
		let view = NSHostingView(rootView: rootView)
		view.setContentHuggingPriority(.defaultLow, for: .horizontal)
		view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return view
	}

	final class Coordinator: NSObject, NSSplitViewDelegate {
		var leadingView: NSHostingView<Leading>?
		var centerView: NSHostingView<Center>?
		var trailingView: NSHostingView<Trailing>?

		func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
			false
		}

		func splitView(
			_ splitView: NSSplitView,
			shouldCollapseSubview subview: NSView,
			forDoubleClickOnDividerAt dividerIndex: Int
		) -> Bool {
			false
		}

		func splitView(
			_ splitView: NSSplitView,
			constrainMinCoordinate proposedMinimumPosition: CGFloat,
			ofSubviewAt dividerIndex: Int
		) -> CGFloat {
			guard let splitView = splitView as? ProportionalSplitView else {
				return proposedMinimumPosition
			}
			return splitView.minimumPosition(ofDividerAt: dividerIndex)
		}

		func splitView(
			_ splitView: NSSplitView,
			constrainMaxCoordinate proposedMaximumPosition: CGFloat,
			ofSubviewAt dividerIndex: Int
		) -> CGFloat {
			guard let splitView = splitView as? ProportionalSplitView else {
				return proposedMaximumPosition
			}
			return splitView.maximumPosition(ofDividerAt: dividerIndex)
		}
	}
}

final class ProportionalSplitView: NSSplitView {
	var proportions: [CGFloat] = [1, 1, 1]
	var minimumWidths: [CGFloat] = [180, 260, 200]
	private var didApplyInitialDistribution = false

	override func layout() {
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
