import AppKit
import DomainGitInterface
import Foundation
import SwiftUI

struct RepositoryTreeView: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@ObservedObject var viewModel: WorkspaceViewModel
	@State private var expandedNodeIDs: Set<String> = []
	@State private var selectedNodeID: String?
	@FocusState private var isTreeFocused: Bool

	var body: some View {
		Group {
			if viewModel.fileTree.isEmpty {
				EmptyStateView(
					title: "Empty Repository",
					message: "Tracked files will appear here.",
					systemImage: "folder"
				)
			} else {
				HSplitView {
					treePane
						.frame(minWidth: 220, idealWidth: 340, maxWidth: 520)

					RepositoryFilePreviewPane(
						node: selectedItem?.node,
						preview: viewModel.filePreview
					)
					.frame(minWidth: 260, idealWidth: 620, maxWidth: .infinity)
				}
			}
		}
		.navigationTitle("Tree")
		.navigationSubtitle("Repository files")
		.onChange(of: viewModel.repositoryURL) {
			expandedNodeIDs = []
			selectedNodeID = nil
		}
	}

	private var treePane: some View {
		List(visibleItems, selection: $selectedNodeID) { item in
			RepositoryTreeRow(
				item: item,
				expandedNodeIDs: $expandedNodeIDs,
				onSelect: {
					selectedNodeID = item.id
					isTreeFocused = true
				}
			)
			.tag(item.id)
			.listRowSeparator(.hidden)
			.listRowInsets(
				EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 10)
			)
		}
		.listStyle(.inset)
		.focused($isTreeFocused)
		.onKeyPress(.rightArrow, action: expandSelectedNode)
		.onKeyPress(.leftArrow, action: collapseSelectedNode)
		.safeAreaInset(edge: .top, spacing: 0) {
			RepositoryTreeHeader(statistics: statistics)
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			if let selectedItem {
				RepositoryTreeSelectionBar(node: selectedItem.node)
			}
		}
		.task(id: selectedNodeID) {
			try? await Task.sleep(for: .milliseconds(1))
			guard !Task.isCancelled else { return }
			viewModel.didSelectTreeNode(selectedItem?.node)
		}
		.task {
			await Task.yield()
			isTreeFocused = true
		}
	}

	private var visibleItems: [RepositoryTreeItem] {
		RepositoryTreeLayoutBuilder.build(
			nodes: viewModel.fileTree,
			expandedNodeIDs: expandedNodeIDs
		)
	}

	private var statistics: (directories: Int, files: Int) {
		RepositoryTreeLayoutBuilder.statistics(in: viewModel.fileTree)
	}

	private var selectedItem: RepositoryTreeItem? {
		visibleItems.first { $0.id == selectedNodeID }
	}

	private var treeAnimation: Animation {
		reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
	}

	private func expandSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem,
			selectedItem.node.isDirectory,
			!expandedNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				expandedNodeIDs.formUnion([selectedNodeID])
			}
		}
		return .handled
	}

	private func collapseSelectedNode() -> KeyPress.Result {
		guard
			let selectedItem,
			selectedItem.node.isDirectory,
			expandedNodeIDs.contains(selectedItem.id)
		else { return .ignored }

		let selectedNodeID = selectedItem.id
		Task { @MainActor in
			await Task.yield()
			withAnimation(treeAnimation) {
				expandedNodeIDs.subtract([selectedNodeID])
			}
		}
		return .handled
	}
}

private struct RepositoryFilePreviewPane: View {
	let node: RepositoryTreeNode?
	let preview: RepositoryFilePreview

	var body: some View {
		previewContent
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.safeAreaInset(edge: .top, spacing: 0) {
				RepositoryFilePreviewHeader(node: node, byteCount: preview.byteCount)
			}
	}

	@ViewBuilder
	private var previewContent: some View {
		if let node {
			if node.isDirectory {
				EmptyStateView(
					title: node.name,
					message: "\(node.children.count) items",
					systemImage: "folder"
				)
			} else {
				switch preview {
				case .none:
					EmptyStateView(
						title: "No Preview",
						message: "Select the file again to load its preview.",
						systemImage: "doc.text.magnifyingglass"
					)
				case .loading:
					LoadingStateView(
						title: "Loading Preview",
						message: "Reading the selected file."
					)
				case .text(let content, _):
					RepositoryTextPreview(content: content)
				case .image(let data):
					RepositoryImagePreview(data: data)
				case .unsupported(let byteCount):
					EmptyStateView(
						title: "Preview Unavailable",
						message: ByteCountFormatter.string(
							fromByteCount: Int64(byteCount),
							countStyle: .file
						),
						systemImage: "doc.questionmark"
					)
				case .failure(let message):
					EmptyStateView(
						title: "Unable to Load Preview",
						message: message,
						systemImage: "exclamationmark.triangle"
					)
				}
			}
		} else {
			EmptyStateView(
				title: "No File Selected",
				message: "Select a file in the tree to preview it.",
				systemImage: "doc.text.magnifyingglass"
			)
		}
	}
}

private struct RepositoryFilePreviewHeader: View {
	let node: RepositoryTreeNode?
	let byteCount: Int?

	var body: some View {
		HStack(spacing: 9) {
			Image(systemName: node?.isDirectory == true ? "folder" : "doc.text")
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.secondary)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 1) {
				Text(node?.name ?? "Preview")
					.font(.callout.weight(.medium))
					.lineLimit(1)

				if let node {
					Text(node.path)
						.font(.caption2)
						.foregroundStyle(.tertiary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}

			Spacer(minLength: 12)

			if let byteCount {
				Text(
					ByteCountFormatter.string(
						fromByteCount: Int64(byteCount),
						countStyle: .file
					)
				)
				.font(.caption)
				.foregroundStyle(.secondary)
			}
		}
		.frame(minHeight: 34)
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.background(.bar)
		.accessibilityElement(children: .combine)
	}
}

private struct RepositoryTextPreview: View {
	let content: String

	var body: some View {
		RepositoryFindableTextView(content: content)
			.background(
				Color(nsColor: .controlBackgroundColor),
				in: RoundedRectangle(cornerRadius: 12, style: .continuous)
			)
			.overlay {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 0.5)
			}
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.padding(16)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}
}

private struct RepositoryFindableTextView: NSViewRepresentable {
	let content: String

	func makeNSView(context: Context) -> RepositoryFindableTextScrollView {
		let scrollView = RepositoryFindableTextScrollView()
		let textView = scrollView.textView

		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true

		textView.isEditable = false
		textView.isSelectable = true
		textView.isRichText = false
		textView.drawsBackground = false
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
		textView.textColor = .labelColor
		textView.textContainerInset = NSSize(width: 16, height: 16)
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = true
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.containerSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.string = content
		textView.setAccessibilityLabel("File Contents")
		scrollView.updateDocumentSize()

		return scrollView
	}

	func updateNSView(_ scrollView: RepositoryFindableTextScrollView, context: Context) {
		let textView = scrollView.textView
		guard textView.string != content else { return }

		textView.string = content
		scrollView.updateDocumentSize()
		textView.scrollToBeginningOfDocument(nil)
	}
}

private final class RepositoryFindableTextScrollView: NSScrollView {
	let textView = NSTextView()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		documentView = textView
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError()
	}

	override func layout() {
		super.layout()
		updateDocumentSize()
	}

	func updateDocumentSize() {
		guard
			let textContainer = textView.textContainer,
			let layoutManager = textView.layoutManager
		else { return }

		layoutManager.ensureLayout(for: textContainer)
		let usedRect = layoutManager.usedRect(for: textContainer)
		let inset = textView.textContainerInset
		let viewportSize = contentView.bounds.size
		let documentSize = NSSize(
			width: max(viewportSize.width, ceil(usedRect.width + inset.width * 2)),
			height: max(viewportSize.height, ceil(usedRect.height + inset.height * 2))
		)

		guard textView.frame.size != documentSize else { return }
		textView.setFrameSize(documentSize)
	}
}

private struct RepositoryImagePreview: View {
	let data: Data

	var body: some View {
		if let image = NSImage(data: data) {
			Image(nsImage: image)
				.resizable()
				.scaledToFit()
				.padding(24)
				.accessibilityLabel("Image Preview")
		} else {
			EmptyStateView(
				title: "Preview Unavailable",
				message: "The image format could not be decoded.",
				systemImage: "photo.badge.exclamationmark"
			)
		}
	}
}

private struct RepositoryTreeHeader: View {
	let statistics: (directories: Int, files: Int)

	var body: some View {
		HStack(spacing: 10) {
			Label("\(statistics.directories) folders", systemImage: "folder")
			Label("\(statistics.files) files", systemImage: "doc")
				.foregroundStyle(.secondary)
			Spacer()
		}
		.font(.caption)
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.bar)
	}
}

private struct RepositoryTreeSelectionBar: View {
	let node: RepositoryTreeNode

	var body: some View {
		HStack(spacing: 7) {
			Image(systemName: node.isDirectory ? "folder" : "doc")
				.symbolRenderingMode(.hierarchical)
				.accessibilityHidden(true)
			Text(node.path)
				.lineLimit(1)
				.truncationMode(.middle)
			Spacer()
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 12)
		.padding(.vertical, 7)
		.background(.bar)
		.accessibilityElement(children: .combine)
	}
}

private struct RepositoryTreeRow: View {
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	let item: RepositoryTreeItem
	@Binding var expandedNodeIDs: Set<String>
	let onSelect: () -> Void

	private var isExpanded: Bool {
		expandedNodeIDs.contains(item.id)
	}

	var body: some View {
		HStack(spacing: 6) {
			RepositoryTreeGuide(item: item)

			if item.node.isDirectory {
				Button(action: toggleExpansion) {
					Image(systemName: "chevron.right")
						.font(.system(size: 9, weight: .semibold))
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.frame(width: 12, height: 18)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(isExpanded ? "Collapse \(item.node.name)" : "Expand \(item.node.name)")
			} else {
				Color.clear
					.frame(width: 12, height: 18)
					.accessibilityHidden(true)
			}

			Image(systemName: symbolName)
				.foregroundStyle(symbolColor)
				.frame(width: 17)
				.accessibilityHidden(true)

			Text(item.node.name)
				.lineLimit(1)
				.truncationMode(.middle)

			Spacer(minLength: 8)

			if item.node.isDirectory {
				Text(item.node.children.count, format: .number)
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.tertiary)
			}
		}
		.frame(minHeight: 24)
		.contentShape(.rect)
		.simultaneousGesture(
			TapGesture()
				.onEnded {
					Task { @MainActor in
						await Task.yield()
						onSelect()
					}
				}
		)
		.simultaneousGesture(
			TapGesture(count: 2)
				.onEnded {
					guard item.node.isDirectory else { return }
					Task { @MainActor in
						await Task.yield()
						toggleExpansion()
					}
				}
		)
		.help(item.node.path)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
	}

	private var accessibilityLabel: String {
		if item.node.isDirectory {
			return "\(item.node.name), folder, \(item.node.children.count) items"
		}
		return "\(item.node.name), file"
	}

	private var symbolName: String {
		if item.node.isDirectory {
			return "folder.fill"
		}

		switch item.node.name.split(separator: ".").last?.lowercased() {
		case "swift":
			return "swift"
		case "md", "markdown", "rtf":
			return "doc.richtext"
		case "json", "plist", "yaml", "yml":
			return "curlybraces"
		case "png", "jpg", "jpeg", "gif", "heic", "svg":
			return "photo"
		case "sh", "zsh", "bash":
			return "terminal"
		default:
			return "doc.text"
		}
	}

	private var symbolColor: Color {
		if item.node.isDirectory {
			return .accentColor
		}
		if item.node.name.hasSuffix(".swift") {
			return .orange
		}
		return .secondary
	}

	private func toggleExpansion() {
		let animation: Animation =
			reduceMotion
			? .easeOut(duration: 0.12)
			: .spring(response: 0.28, dampingFraction: 1)
		withAnimation(animation) {
			if isExpanded {
				expandedNodeIDs.remove(item.id)
			} else {
				expandedNodeIDs.insert(item.id)
			}
		}
	}
}

private struct RepositoryTreeGuide: View {
	let item: RepositoryTreeItem

	private let indentation: CGFloat = 16

	var body: some View {
		Canvas { context, size in
			guard item.depth > 0 else { return }
			let color = Color(nsColor: .separatorColor).opacity(0.7)
			let rowMidY = size.height / 2

			if item.depth > 1 {
				for level in 0..<(item.depth - 1)
				where item.ancestorHasFollowingSibling[level] {
					let x = CGFloat(level) * indentation + indentation / 2
					var path = Path()
					path.move(to: CGPoint(x: x, y: 0))
					path.addLine(to: CGPoint(x: x, y: size.height))
					context.stroke(path, with: .color(color), lineWidth: 1)
				}
			}

			let branchX = CGFloat(item.depth - 1) * indentation + indentation / 2
			var branch = Path()
			branch.move(to: CGPoint(x: branchX, y: 0))
			branch.addLine(
				to: CGPoint(
					x: branchX,
					y: item.isLastSibling ? rowMidY : size.height
				)
			)
			branch.move(to: CGPoint(x: branchX, y: rowMidY))
			branch.addLine(to: CGPoint(x: size.width, y: rowMidY))
			context.stroke(branch, with: .color(color), lineWidth: 1)
		}
		.frame(width: CGFloat(item.depth) * indentation, height: 24)
		.accessibilityHidden(true)
	}
}
