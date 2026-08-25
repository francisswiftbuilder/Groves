import DomainGitInterface
import SwiftUI

struct DiffLineView: View {
	let line: DiffLine
	let filePath: String?
	let searchText: String
	let showsOldLineNumbers: Bool
	let showsNewLineNumbers: Bool
	let lineAction: GitDiffLineAction?
	let hunkActions: [GitDiffHunkAction]
	let isLoading: Bool
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void
	let onApplyHunk: (GitDiffHunkSelection, GitDiffHunkAction) -> Void

	var body: some View {
		Group {
			if line.kind == .hunk {
				hunkHeader
			} else {
				sourceLine
			}
		}
	}

	private var sourceLine: some View {
		HStack(spacing: 0) {
			lineActionButton
			lineNumber(line.oldLineNumber, isVisible: showsOldLineNumbers)
			lineNumber(line.newLineNumber, isVisible: showsNewLineNumbers)
			changeMarker

			Text(
				DiffSyntaxHighlighter.styledText(
					line.sourceText,
					filePath: filePath,
					kind: line.kind,
					changedRange: line.changedRange,
					searchText: searchText
				)
			)
			.font(.system(size: 12, design: .monospaced))
			.padding(.leading, 8)
			.padding(.trailing, 12)
			.padding(.vertical, 1)
			.lineLimit(1)
			.fixedSize(horizontal: true, vertical: false)
			.multilineTextAlignment(.leading)

			Spacer(minLength: 12)
		}
		.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
		.background { backgroundColor }
		.contextMenu { lineContextMenu }
	}

	private var hunkHeader: some View {
		HStack(spacing: 8) {
			Image(systemName: "arrow.up.and.down.text.horizontal")
				.foregroundStyle(.secondary)
				.frame(width: 20)
				.accessibilityHidden(true)

			Text(line.text)
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
				.lineLimit(1)

			Spacer(minLength: 12)

			if let primaryHunkAction, let selection = line.hunkSelection {
				Button(primaryHunkAction.title) {
					onApplyHunk(selection, primaryHunkAction)
				}
				.buttonStyle(.bordered)
				.controlSize(.small)
				.disabled(isLoading)
			}

			if !secondaryHunkActions.isEmpty, let selection = line.hunkSelection {
				Menu("Hunk Actions", systemImage: "ellipsis.circle") {
					ForEach(secondaryHunkActions, id: \.self) { action in
						if action.isDestructive {
							Button(action.title, systemImage: action.systemImage, role: .destructive) {
								onApplyHunk(selection, action)
							}
						} else {
							Button(action.title, systemImage: action.systemImage) {
								onApplyHunk(selection, action)
							}
						}
					}
				}
				.menuStyle(.borderlessButton)
				.fixedSize()
				.disabled(isLoading)
				.help("Hunk Actions")
			}
		}
		.padding(.horizontal, 8)
		.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
		.background(Color.primary.opacity(0.05))
	}

	private var primaryHunkAction: GitDiffHunkAction? {
		hunkActions.first { !$0.isDestructive }
	}

	private var secondaryHunkActions: [GitDiffHunkAction] {
		hunkActions.filter { $0 != primaryHunkAction }
	}

	private var changeMarker: some View {
		Text(markerText)
			.font(.system(.caption, design: .monospaced, weight: .semibold))
			.foregroundStyle(markerColor)
			.frame(width: 18)
			.accessibilityHidden(true)
	}

	private var markerText: String {
		switch line.kind {
		case .addition: return "+"
		case .deletion: return "−"
		case .metadata, .hunk, .context: return ""
		}
	}

	private var markerColor: Color {
		switch line.kind {
		case .addition: return .green
		case .deletion: return .red
		case .metadata, .hunk, .context: return .secondary
		}
	}

	@ViewBuilder
	private var lineActionButton: some View {
		if line.showsAction, let selection = line.selection, let lineAction {
			Button {
				onApplyLine(selection, lineAction)
			} label: {
				Image(systemName: lineAction.systemImage)
					.frame(width: 20, height: 20)
			}
			.buttonStyle(.borderless)
			.tint(lineAction.tint)
			.frame(width: 28, height: 20)
			.disabled(isLoading)
			.help(lineAction.title)
			.accessibilityLabel(lineAction.title)
			.accessibilityHint(line.sourceText)
		} else {
			Color.clear
				.frame(width: 28, height: 20)
				.accessibilityHidden(true)
		}
	}

	@ViewBuilder
	private var lineContextMenu: some View {
		if line.showsAction, let selection = line.selection, let lineAction {
			Button(lineAction.title, systemImage: lineAction.systemImage) {
				onApplyLine(selection, lineAction)
			}
			.disabled(isLoading)
		}
	}

	private func lineNumber(_ number: Int?, isVisible: Bool) -> some View {
		Text(number.map(String.init) ?? "")
			.font(.system(.caption2, design: .monospaced))
			.foregroundStyle(.tertiary)
			.frame(width: isVisible ? 38 : 0, alignment: .trailing)
			.padding(.trailing, isVisible ? 8 : 0)
			.opacity(isVisible ? 1 : 0)
			.accessibilityHidden(true)
	}

	private var backgroundColor: Color {
		switch line.kind {
		case .addition: return Color.green.opacity(0.08)
		case .deletion: return Color.red.opacity(0.08)
		case .metadata, .hunk, .context: return .clear
		}
	}
}
