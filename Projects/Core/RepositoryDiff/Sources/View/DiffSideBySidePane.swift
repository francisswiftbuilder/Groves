import SwiftUI

struct DiffSideBySidePane: View {
	let line: DiffLine?
	let filePath: String?
	let searchText: String
	let activeSearchRange: DiffTextRange?
	let isOld: Bool

	var body: some View {
		HStack(alignment: .top, spacing: 0) {
			Text(lineNumber)
				.font(.system(.caption2, design: .monospaced))
				.foregroundStyle(.tertiary)
				.frame(width: 42, alignment: .trailing)
				.padding(.trailing, 8)
				.accessibilityHidden(true)

			Text(marker)
				.font(.system(.caption, design: .monospaced, weight: .semibold))
				.foregroundStyle(markerColor)
				.frame(width: 18)
				.accessibilityHidden(true)

			if let line {
				Text(
					DiffSyntaxHighlighter.styledText(
						line.sourceText,
						filePath: filePath,
						kind: line.kind,
						changedRange: line.changedRange,
						searchText: searchText,
						activeSearchRange: activeSearchRange
					)
				)
				.font(.system(size: 12, design: .monospaced))
				.padding(.leading, 8)
				.padding(.trailing, 12)
				.padding(.vertical, 1)
				.fixedSize(horizontal: false, vertical: true)
				.textSelection(.enabled)
			}

			Spacer(minLength: 12)
		}
		.frame(maxWidth: .infinity, minHeight: 20, alignment: .topLeading)
		.background(backgroundColor)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(accessibilityLabel)
	}

	private var lineNumber: String {
		guard let line else { return "" }
		return (isOld ? line.oldLineNumber : line.newLineNumber).map(String.init) ?? ""
	}

	private var marker: String {
		guard let line else { return "" }
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
		guard let line else { return .secondary }
		switch line.kind {
		case .addition:
			return .green
		case .deletion:
			return .red
		case .metadata, .hunk, .context:
			return .secondary
		}
	}

	private var backgroundColor: Color {
		guard let line else { return Color.primary.opacity(0.025) }
		switch line.kind {
		case .addition:
			return Color.green.opacity(0.08)
		case .deletion:
			return Color.red.opacity(0.08)
		case .metadata, .hunk, .context:
			return .clear
		}
	}

	private var accessibilityLabel: String {
		guard let line else { return isOld ? "No previous line" : "No current line" }
		let side = isOld ? "Previous" : "Current"
		return "\(side) line \(lineNumber), \(line.sourceText)"
	}
}
