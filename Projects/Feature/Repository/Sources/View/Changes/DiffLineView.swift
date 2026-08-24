import DomainGitInterface
import SwiftUI

struct DiffLineView: View {
	let line: DiffLine
	let showsOldLineNumbers: Bool
	let showsNewLineNumbers: Bool
	let action: GitDiffLineAction?
	let isLoading: Bool
	let onApply: (GitDiffLineSelection, GitDiffLineAction) -> Void

	var body: some View {
		HStack(spacing: 0) {
			lineActionButton
			lineNumber(line.oldLineNumber, isVisible: showsOldLineNumbers)
			lineNumber(line.newLineNumber, isVisible: showsNewLineNumbers)
			changeMarker

			Text(line.sourceText.isEmpty ? " " : line.sourceText)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(.primary)
				.padding(.leading, 10)
				.padding(.trailing, 12)
				.padding(.vertical, 1)
				.lineLimit(1)
				.fixedSize(horizontal: true, vertical: false)
				.multilineTextAlignment(.leading)
				.textSelection(.enabled)
		}
		.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
		.background {
			backgroundColor
		}
	}

	private var changeMarker: some View {
		Text(markerText)
			.font(.system(.caption, design: .monospaced, weight: .semibold))
			.foregroundStyle(markerColor)
			.frame(width: 20)
			.accessibilityHidden(true)
	}

	private var markerText: String {
		switch line.kind {
		case .addition:
			return "+"
		case .deletion:
			return "−"
		case .metadata, .hunk, .context:
			return ""
		}
	}

	private var markerColor: Color {
		switch line.kind {
		case .addition:
			return .green
		case .deletion:
			return .red
		case .metadata, .hunk, .context:
			return .secondary
		}
	}

	@ViewBuilder
	private var lineActionButton: some View {
		if line.showsAction, let selection = line.selection, let action {
			Button {
				onApply(selection, action)
			} label: {
				Label(action.buttonTitle, systemImage: action.systemImage)
					.font(.caption2.weight(.semibold))
			}
			.buttonStyle(.bordered)
			.controlSize(.mini)
			.tint(action.tint)
			.frame(width: 68, height: 20)
			.disabled(isLoading)
			.help(action.title)
			.accessibilityLabel(action.title)
			.accessibilityHint(line.sourceText)
		} else {
			Color.clear
				.frame(width: 68, height: 20)
				.accessibilityHidden(true)
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
		case .addition:
			return Color.green.opacity(0.08)
		case .deletion:
			return Color.red.opacity(0.08)
		case .metadata, .hunk, .context:
			return .clear
		}
	}
}
