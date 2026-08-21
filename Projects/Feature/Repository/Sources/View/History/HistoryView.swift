import SwiftUI

struct HistoryView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var selectedFileID: CommitDiffFile.ID?

	var body: some View {
		Group {
			if viewModel.commitGraphItems.isEmpty {
				EmptyStateView(
					title: "No Commits",
					message: "Commit history will appear after the first commit.",
					systemImage: "point.3.connected.trianglepath.dotted"
				)
			} else {
				EqualWidthHSplitView(
					proportions: [0.30, 0.46, 0.24],
					minimumWidths: [220, 300, 210]
				) {
					historyList
						.frame(maxWidth: .infinity)
				} center: {
					CommitDiffView(
						file: selectedFile,
						changedFileCount: commitFiles.count,
						isLoading: viewModel.isLoadingCommitDiff
					)
					.id(viewModel.selectedCommitID)
					.frame(maxWidth: .infinity)
				} trailing: {
					CommitInspectorView(
						commit: viewModel.selectedCommit,
						files: commitFiles,
						isLoadingFiles: viewModel.isLoadingCommitDiff,
						selectedFileID: $selectedFileID
					)
					.frame(maxWidth: .infinity)
				}
			}
		}
		.navigationTitle(viewModel.repositoryName)
		.navigationSubtitle(viewModel.currentBranchName)
		.onAppear {
			viewModel.didChangeSelectedCommit()
			selectFirstFileIfNeeded()
		}
		.onChange(of: viewModel.selectedCommitID) { _, _ in
			selectedFileID = nil
			viewModel.didChangeSelectedCommit()
		}
		.onChange(of: viewModel.selectedCommitFiles.map(\.id)) { _, _ in
			selectFirstFileIfNeeded()
		}
	}

	private var historyList: some View {
		ScrollViewReader { proxy in
			VStack(spacing: 0) {
				HStack {
					Menu {
						Text("All branches are shown")
					} label: {
						Label("All Branches", systemImage: "chevron.down")
							.labelStyle(.titleAndIcon)
							.font(.subheadline.weight(.semibold))
					}
					.menuStyle(.borderlessButton)
					Spacer()
					Image(systemName: "slider.horizontal.3")
						.foregroundStyle(.secondary)
						.accessibilityHidden(true)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)

				Divider()

				List(selection: $viewModel.selectedCommitID) {
					ForEach(viewModel.commitGraphItems) { item in
						CommitGraphRow(
							item: item,
							isSelected: item.id == viewModel.selectedCommitID
						)
						.equatable()
						.id(item.id)
						.tag(item.id)
						.contentShape(.rect)
						.listRowInsets(.init())
						.listRowSeparator(.hidden)
					}
				}
				.listStyle(.plain)
			}
			.task(id: viewModel.historyFocusRequest) {
				await scrollToFocusedCommit(using: proxy)
			}
		}
	}

	private var commitFiles: [CommitDiffFile] {
		viewModel.selectedCommitFiles
	}

	private var selectedFile: CommitDiffFile? {
		guard !commitFiles.isEmpty else { return nil }
		return commitFiles.first { $0.id == selectedFileID } ?? commitFiles.first
	}

	private func selectFirstFileIfNeeded() {
		guard !commitFiles.isEmpty else {
			selectedFileID = nil
			return
		}
		guard !commitFiles.contains(where: { $0.id == selectedFileID }) else { return }
		selectedFileID = commitFiles.first?.id
	}

	private func scrollToFocusedCommit(using proxy: ScrollViewProxy) async {
		guard let request = viewModel.historyFocusRequest else { return }
		await Task.yield()
		guard !Task.isCancelled else { return }
		guard viewModel.commitGraphItems.contains(where: { $0.id == request.commitID }) else {
			return
		}

		if request.isAnimated && !reduceMotion {
			withAnimation(.easeInOut(duration: 0.2)) {
				proxy.scrollTo(request.commitID, anchor: .center)
			}
		} else {
			proxy.scrollTo(request.commitID, anchor: .center)
		}
	}
}

private struct CommitGraphRow: View, Equatable {
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

private struct CommitGraphReference: View {
	let reference: String

	var body: some View {
		Label(displayName, systemImage: systemImage)
			.labelStyle(.titleAndIcon)
			.font(.caption2.weight(.medium))
			.lineLimit(1)
			.truncationMode(.middle)
			.foregroundStyle(referenceColor)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(referenceColor.opacity(0.10), in: Capsule())
			.frame(maxWidth: 132)
			.help(reference)
	}

	private var referenceColor: Color {
		if reference.contains("HEAD") {
			return Color(nsColor: .controlAccentColor)
		}
		if reference.contains("tag:") {
			return .orange
		}
		if reference.contains("origin/") {
			return .blue
		}
		return Color(nsColor: .secondaryLabelColor)
	}

	private var displayName: String {
		reference
			.replacingOccurrences(of: "HEAD -> ", with: "")
			.replacingOccurrences(of: "tag: ", with: "")
	}

	private var systemImage: String {
		if reference.contains("tag:") {
			return "tag.fill"
		}
		if reference.contains("origin/") {
			return "cloud.fill"
		}
		return "arrow.triangle.branch"
	}
}

private struct CommitGraphReferenceOverflow: View {
	let count: Int

	var body: some View {
		Text("+\(count)")
			.font(.caption2.weight(.semibold))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(Color(nsColor: .quaternaryLabelColor).opacity(0.16), in: Capsule())
	}
}

private struct CommitGraphLaneView: View {
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

private enum CommitGraphMetrics {
	static let leadingInset: CGFloat = 10
	static let laneWidth: CGFloat = 16
	static let trailingInset: CGFloat = 4
	static let contentSpacing: CGFloat = 10
	static let rowHeight: CGFloat = 52

	static func width(for laneCapacity: Int) -> CGFloat {
		leadingInset + CGFloat(laneCapacity) * laneWidth + trailingInset
	}
}
