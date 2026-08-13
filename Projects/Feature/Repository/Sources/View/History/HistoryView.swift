import SwiftUI

struct HistoryView: View {
	@ObservedObject var viewModel: WorkspaceViewModel

	var body: some View {
		Group {
			if viewModel.commitGraphItems.isEmpty {
				EmptyStateView(
					title: "No Commits",
					message: "Commit history will appear after the first commit.",
					systemImage: "point.3.connected.trianglepath.dotted"
				)
			} else {
				List(selection: $viewModel.selectedCommitID) {
					ForEach(viewModel.commitGraphItems) { item in
						CommitGraphRow(item: item)
							.tag(item.id)
							.listRowSeparator(.hidden)
					}
				}
				.listStyle(.inset)
			}
		}
		.navigationTitle("History")
		.navigationSubtitle("\(viewModel.commitGraphItems.count) commits")
	}
}

private struct CommitGraphRow: View {
	let item: CommitGraphItem

	var body: some View {
		HStack(spacing: 12) {
			CommitGraphLaneView(item: item)
				.frame(width: graphWidth, height: 42)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				HStack(spacing: 6) {
					Text(item.commit.subject)
						.lineLimit(1)
					ForEach(item.commit.references, id: \.self) { reference in
						Text(reference)
							.font(.caption2)
							.padding(.horizontal, 5)
							.padding(.vertical, 2)
							.background {
								Capsule().fill(.blue.opacity(0.14))
							}
					}
				}

				HStack(spacing: 8) {
					Text(item.commit.shortHash)
						.font(.system(.caption, design: .monospaced))
					Text(item.commit.author)
					Text(item.commit.date, style: .relative)
				}
				.font(.caption)
				.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 5)
		.accessibilityElement(children: .combine)
	}

	private var graphWidth: CGFloat {
		CGFloat(max(item.topLanes.count, item.bottomLanes.count, item.lane + 1)) * 16
	}
}

private struct CommitGraphLaneView: View {
	let item: CommitGraphItem

	var body: some View {
		Canvas { context, size in
			let laneWidth: CGFloat = 16
			let centerY = size.height / 2
			let laneX = CGFloat(item.lane) * laneWidth + laneWidth / 2

			for lane in 0..<item.topLanes.count {
				let x = CGFloat(lane) * laneWidth + laneWidth / 2
				var path = Path()
				path.move(to: CGPoint(x: x, y: 0))
				path.addLine(to: CGPoint(x: x, y: centerY))
				context.stroke(path, with: .color(color(for: lane)), lineWidth: 2)
			}

			for lane in 0..<item.bottomLanes.count {
				let x = CGFloat(lane) * laneWidth + laneWidth / 2
				var path = Path()
				path.move(to: CGPoint(x: x, y: centerY))
				path.addLine(to: CGPoint(x: x, y: size.height))
				context.stroke(path, with: .color(color(for: lane)), lineWidth: 2)
			}

			let circle = Path(ellipseIn: CGRect(x: laneX - 4, y: centerY - 4, width: 8, height: 8))
			context.fill(circle, with: .color(color(for: item.lane)))
		}
	}

	private func color(for lane: Int) -> Color {
		let colors: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan]
		return colors[lane % colors.count]
	}
}
