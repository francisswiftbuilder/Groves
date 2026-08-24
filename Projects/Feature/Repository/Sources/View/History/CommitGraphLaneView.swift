import SwiftUI

struct CommitGraphLaneView: View {
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast
	let item: CommitGraphItem
	let isSelected: Bool

	var body: some View {
		Canvas { context, size in
			let centerY = size.height / 2

			for segment in item.incomingSegments {
				strokeConnection(
					from: CGPoint(x: xPosition(for: segment.fromLane), y: 0),
					to: CGPoint(x: xPosition(for: segment.toLane), y: centerY),
					colorIndex: segment.colorIndex,
					in: &context
				)
			}

			for segment in item.outgoingSegments {
				strokeConnection(
					from: CGPoint(x: xPosition(for: segment.fromLane), y: centerY),
					to: CGPoint(x: xPosition(for: segment.toLane), y: size.height),
					colorIndex: segment.colorIndex,
					in: &context
				)
			}

			let laneX = xPosition(for: item.lane)
			let node = nodePath(
				center: CGPoint(x: laneX, y: centerY),
				isMerge: item.commit.parentHashes.count > 1
			)
			let nodeColor =
				isSelected
				? Color(nsColor: .selectedControlTextColor)
				: lineColor(colorIndex: item.nodeColorIndex)
			context.fill(
				node,
				with: .color(
					isSelected ? nodeColor : Color(nsColor: .windowBackgroundColor)
				)
			)
			context.stroke(
				node,
				with: .color(nodeColor),
				lineWidth: isSelected ? 2.25 : 1.75
			)
		}
	}

	private func lineColor(colorIndex: Int) -> Color {
		let colors: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan]
		let opacity = colorSchemeContrast == .increased ? 0.95 : 0.76
		return colors[colorIndex % colors.count].opacity(opacity)
	}

	private func xPosition(for lane: Int) -> CGFloat {
		CommitGraphMetrics.leadingInset
			+ CGFloat(lane) * CommitGraphMetrics.laneWidth
			+ CommitGraphMetrics.laneWidth / 2
	}

	private func strokeConnection(
		from start: CGPoint,
		to end: CGPoint,
		colorIndex: Int,
		in context: inout GraphicsContext
	) {
		var path = Path()
		path.move(to: start)
		if start.x == end.x {
			path.addLine(to: end)
		} else {
			let verticalDistance = end.y - start.y
			let transitionHeight = min(12, max(6, verticalDistance * 0.46))
			let transitionEnd = CGPoint(
				x: end.x,
				y: min(end.y, start.y + transitionHeight)
			)
			path.addCurve(
				to: transitionEnd,
				control1: CGPoint(x: start.x, y: start.y + transitionHeight * 0.64),
				control2: CGPoint(x: end.x, y: start.y + transitionHeight * 0.36)
			)
			path.addLine(to: end)
		}
		context.stroke(
			path,
			with: .color(lineColor(colorIndex: colorIndex)),
			style: graphStrokeStyle
		)
	}

	private func nodePath(center: CGPoint, isMerge: Bool) -> Path {
		let radius: CGFloat = isSelected ? 5 : 4
		if isMerge {
			var path = Path()
			path.move(to: CGPoint(x: center.x, y: center.y - radius))
			path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
			path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
			path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
			path.closeSubpath()
			return path
		}

		let frame = CGRect(
			x: center.x - radius,
			y: center.y - radius,
			width: radius * 2,
			height: radius * 2
		)
		return Path(ellipseIn: frame)
	}

	private var graphStrokeStyle: StrokeStyle {
		let lineWidth: CGFloat = colorSchemeContrast == .increased ? 1.75 : 1.5
		return StrokeStyle(
			lineWidth: lineWidth,
			lineCap: .round,
			lineJoin: .round
		)
	}
}
