import SwiftUI

struct DiffView: View {
	let diff: String

	var body: some View {
		if diff.isEmpty {
			EmptyStateView(
				title: "No Diff Selected",
				message: "Select a tracked text change to inspect its diff.",
				systemImage: "doc.text.magnifyingglass"
			)
		} else {
			ScrollView([.horizontal, .vertical]) {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(diffLines) { line in
						DiffLineView(line: line)
					}
				}
				.padding(.vertical, 8)
				.fixedSize(horizontal: true, vertical: true)
			}
			.defaultScrollAnchor(.topLeading)
			.background {
				Color(nsColor: .textBackgroundColor)
			}
		}
	}

	private var diffLines: [DiffLine] {
		diff.split(separator: "\n", omittingEmptySubsequences: false)
			.enumerated()
			.map { DiffLine(number: $0.offset, text: String($0.element)) }
	}
}

private struct DiffLine: Identifiable {
	let number: Int
	let text: String

	var id: Int { number }
}

private struct DiffLineView: View {
	let line: DiffLine

	var body: some View {
		HStack(spacing: 0) {
			Text(line.number + 1, format: .number)
				.font(.system(.caption2, design: .monospaced))
				.foregroundStyle(.tertiary)
				.frame(width: 42, alignment: .trailing)
				.padding(.trailing, 9)
				.accessibilityHidden(true)

			Text(line.text.isEmpty ? " " : line.text)
				.font(.system(size: 12, design: .monospaced))
				.foregroundStyle(foregroundColor)
				.padding(.leading, 10)
				.padding(.trailing, 12)
				.padding(.vertical, 1)
				.textSelection(.enabled)
		}
		.background {
			backgroundColor
		}
	}

	private var foregroundColor: Color {
		if line.text.hasPrefix("+") && !line.text.hasPrefix("+++") {
			return .green
		}
		if line.text.hasPrefix("-") && !line.text.hasPrefix("---") {
			return .red
		}
		if line.text.hasPrefix("@@") {
			return .blue
		}
		return .primary
	}

	private var backgroundColor: Color {
		if line.text.hasPrefix("+") && !line.text.hasPrefix("+++") {
			return Color.green.opacity(0.08)
		}
		if line.text.hasPrefix("-") && !line.text.hasPrefix("---") {
			return Color.red.opacity(0.08)
		}
		return .clear
	}
}
