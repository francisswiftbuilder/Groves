import SwiftUI

struct CommitDiffLineView: View {
	let line: DiffLine
	let showsOldLineNumbers: Bool
	let showsNewLineNumbers: Bool

	var body: some View {
		HStack(spacing: 0) {
			lineNumber(line.oldLineNumber, isVisible: showsOldLineNumbers)
			lineNumber(line.newLineNumber, isVisible: showsNewLineNumbers)
			changeMarker

			Text(line.sourceText.isEmpty ? " " : line.sourceText)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(line.kind == .hunk ? .secondary : .primary)
				.padding(.leading, 10)
				.padding(.trailing, 12)
				.padding(.vertical, 1)
				.lineLimit(1)
				.fixedSize(horizontal: true, vertical: false)
				.textSelection(.enabled)

			Spacer(minLength: 12)
		}
		.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
		.background(backgroundColor)
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
		case .hunk:
			return Color.primary.opacity(0.05)
		case .metadata, .context:
			return .clear
		}
	}
}
