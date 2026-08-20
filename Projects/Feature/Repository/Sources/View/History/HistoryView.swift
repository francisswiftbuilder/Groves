import SwiftUI

struct HistoryView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var selectedFileID: CommitDiffFile.ID?
	@State private var focusScrollTask: Task<Void, Never>?

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
					CommitDiffView(file: selectedFile, changedFileCount: commitFiles.count)
						.id(viewModel.selectedCommitID)
						.frame(maxWidth: .infinity)
				} trailing: {
					CommitInspectorView(
						commit: viewModel.selectedCommit,
						files: commitFiles,
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
		.onChange(of: viewModel.selectedCommitDiff) { _, _ in
			selectFirstFileIfNeeded()
		}
		.onDisappear {
			focusScrollTask?.cancel()
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
						CommitGraphRow(item: item)
							.id(item.id)
							.tag(item.id)
							.listRowSeparator(.hidden)
							.listRowInsets(.init())
					}
				}
				.listStyle(.plain)
			}
			.onAppear {
				scrollToFocusedCommit(using: proxy, animated: false)
			}
			.onChange(of: viewModel.historyFocusRequest) { _, _ in
				scrollToFocusedCommit(using: proxy, animated: true)
			}
			.onChange(of: viewModel.commitGraphItems.count) { _, _ in
				scrollToFocusedCommit(using: proxy, animated: false)
			}
		}
	}

	private var commitFiles: [CommitDiffFile] {
		CommitDiffFileParser.parse(viewModel.selectedCommitDiff)
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

	private func scrollToFocusedCommit(using proxy: ScrollViewProxy, animated: Bool) {
		guard let request = viewModel.historyFocusRequest else { return }
		focusScrollTask?.cancel()
		focusScrollTask = Task { @MainActor in
			await Task.yield()
			await Task.yield()
			try? await Task.sleep(for: .milliseconds(40))
			guard
				!Task.isCancelled,
				viewModel.historyFocusRequest == request,
				viewModel.commitGraphItems.contains(where: { $0.id == request.commitID })
			else { return }

			if animated && request.isAnimated && !reduceMotion {
				withAnimation(.easeInOut(duration: 0.2)) {
					proxy.scrollTo(request.commitID, anchor: .center)
				}
			} else {
				proxy.scrollTo(request.commitID, anchor: .center)
			}
		}
	}
}

private struct CommitGraphRow: View {
	let item: CommitGraphItem

	var body: some View {
		HStack(spacing: CommitGraphMetrics.contentSpacing) {
			CommitGraphLaneView(item: item)
				.frame(
					width: CommitGraphMetrics.width(for: item.visibleLaneCount),
					height: CommitGraphMetrics.rowHeight
				)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 3) {
				Text(item.commit.subject)
					.font(.subheadline.weight(.medium))
					.lineLimit(1)

				HStack(spacing: 7) {
					Image(systemName: "person.crop.circle.fill")
						.foregroundStyle(.tertiary)
						.accessibilityHidden(true)
					Text(item.commit.author)
					Text(item.commit.date.formatted(date: .abbreviated, time: .shortened))
				}
				.font(.caption)
				.foregroundStyle(.secondary)

				if !item.commit.references.isEmpty {
					HStack(spacing: 5) {
						ForEach(item.commit.references.prefix(2), id: \.self) { reference in
							CommitGraphReference(reference: reference)
						}
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, minHeight: CommitGraphMetrics.rowHeight, alignment: .leading)
		.padding(.trailing, 12)
		.accessibilityElement(children: .combine)
	}
}

private struct CommitGraphReference: View {
	let reference: String

	var body: some View {
		Text(reference)
			.font(.caption2.weight(.medium))
			.foregroundStyle(referenceColor)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(referenceColor.opacity(0.12), in: Capsule())
	}

	private var referenceColor: Color {
		reference.contains("HEAD") ? .primary : .blue
	}
}

private struct CommitGraphLaneView: View {
	let item: CommitGraphItem

	var body: some View {
		Canvas { context, size in
			let centerY = size.height / 2

			for (lane, hash) in item.topLanes.enumerated() {
				let sourceX = xPosition(for: lane)
				let sourceColor = color(for: item.topLaneColorIndices[lane])
				strokeLine(
					from: CGPoint(x: sourceX, y: 0),
					to: CGPoint(x: sourceX, y: centerY),
					color: sourceColor,
					in: &context
				)

				if hash == item.commit.hash {
					for parentHash in item.commit.parentHashes {
						guard let destinationLane = item.bottomLanes.firstIndex(of: parentHash) else {
							continue
						}
						strokeConnection(
							from: CGPoint(x: sourceX, y: centerY),
							to: CGPoint(
								x: xPosition(for: destinationLane),
								y: size.height
							),
							color: color(for: item.bottomLaneColorIndices[destinationLane]),
							in: &context
						)
					}
				} else if let destinationLane = item.bottomLanes.firstIndex(of: hash) {
					strokeConnection(
						from: CGPoint(x: sourceX, y: centerY),
						to: CGPoint(
							x: xPosition(for: destinationLane),
							y: size.height
						),
						color: sourceColor,
						in: &context
					)
				}
			}

			let laneX = xPosition(for: item.lane)
			let circle = Path(
				ellipseIn: CGRect(x: laneX - 5, y: centerY - 5, width: 10, height: 10)
			)
			context.fill(circle, with: .color(Color(nsColor: .windowBackgroundColor)))
			context.stroke(
				circle,
				with: .color(color(for: item.topLaneColorIndices[item.lane])),
				lineWidth: 2
			)
		}
	}

	private func color(for colorIndex: Int) -> Color {
		let colors: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan]
		return colors[colorIndex % colors.count]
	}

	private func xPosition(for lane: Int) -> CGFloat {
		CommitGraphMetrics.leadingInset
			+ CGFloat(lane) * CommitGraphMetrics.laneWidth
			+ CommitGraphMetrics.laneWidth / 2
	}

	private func strokeLine(
		from start: CGPoint,
		to end: CGPoint,
		color: Color,
		in context: inout GraphicsContext
	) {
		var path = Path()
		path.move(to: start)
		path.addLine(to: end)
		context.stroke(path, with: .color(color), style: graphStrokeStyle)
	}

	private func strokeConnection(
		from start: CGPoint,
		to end: CGPoint,
		color: Color,
		in context: inout GraphicsContext
	) {
		var path = Path()
		path.move(to: start)
		if start.x == end.x {
			path.addLine(to: end)
		} else {
			let verticalDistance = end.y - start.y
			let curveInset = min(10, verticalDistance / 3)
			let curveStart = CGPoint(x: start.x, y: start.y + curveInset)
			let curveEnd = CGPoint(x: end.x, y: end.y - curveInset)
			let curveHeight = curveEnd.y - curveStart.y

			path.addLine(to: curveStart)
			path.addCurve(
				to: curveEnd,
				control1: CGPoint(x: curveStart.x, y: curveStart.y + curveHeight / 3),
				control2: CGPoint(x: curveEnd.x, y: curveEnd.y - curveHeight / 3)
			)
			path.addLine(to: end)
		}
		context.stroke(path, with: .color(color), style: graphStrokeStyle)
	}

	private var graphStrokeStyle: StrokeStyle {
		StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
	}
}

private enum CommitGraphMetrics {
	static let leadingInset: CGFloat = 18
	static let laneWidth: CGFloat = 20
	static let trailingInset: CGFloat = 2
	static let contentSpacing: CGFloat = 8
	static let rowHeight: CGFloat = 56

	static func width(for laneCapacity: Int) -> CGFloat {
		leadingInset + CGFloat(laneCapacity) * laneWidth + trailingInset
	}
}
