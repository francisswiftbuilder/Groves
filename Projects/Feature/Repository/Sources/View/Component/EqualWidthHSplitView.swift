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
