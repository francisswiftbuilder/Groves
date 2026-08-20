import SwiftUI

struct CommitDiffView: View {
	let file: CommitDiffFile?
	let changedFileCount: Int

	var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if let file {
				diffFooter(file: file)
			}
		}
	}

	private func diffFooter(file: CommitDiffFile) -> some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files changed")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				CommitDiffStatistics(file: file)
			}
			.font(.caption)
			.padding(.horizontal, 16)
			.frame(height: 40)
		}
		.background(.bar)
	}

	@ViewBuilder
	private var diffHeader: some View {
		if let file {
			VStack(alignment: .leading, spacing: 12) {
				Text(file.path.replacingOccurrences(of: "/", with: " / "))
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)

				HStack(spacing: 8) {
					Text("File changed")
						.font(.subheadline.weight(.medium))
					Spacer()
					CommitDiffStatistics(file: file)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 12)
		} else {
			HStack {
				Text("Changes")
					.font(.subheadline.weight(.semibold))
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
	}

	@ViewBuilder
	private var diffContent: some View {
		if file != nil {
			if diffLines.isEmpty {
				EmptyStateView(
					title: "No Text Diff",
					message: "This commit changed a file without a text diff.",
					systemImage: "doc"
				)
			} else {
				GeometryReader { geometry in
					ScrollView([.horizontal, .vertical]) {
						VStack(alignment: .leading, spacing: 0) {
							ForEach(diffLines) { line in
								CommitDiffLineView(
									line: line,
									showsOldLineNumbers: showsOldLineNumbers,
									showsNewLineNumbers: showsNewLineNumbers
								)
							}
						}
						.padding(.vertical, 8)
						.frame(minWidth: max(geometry.size.width, 0), alignment: .leading)
					}
					.defaultScrollAnchor(.topLeading)
				}
			}
		} else {
			EmptyStateView(
				title: "No File Selected",
				message: "Select a changed file to inspect this commit.",
				systemImage: "doc.text.magnifyingglass"
			)
		}
	}

	private var diffLines: [DiffLine] {
		guard let file else { return [] }
		return DiffParser.parse(file.diff).filter { $0.kind != .metadata }
	}

	private var showsOldLineNumbers: Bool {
		diffLines.contains { $0.oldLineNumber != nil }
	}

	private var showsNewLineNumbers: Bool {
		diffLines.contains { $0.newLineNumber != nil }
	}
}

private struct CommitDiffStatistics: View {
	let file: CommitDiffFile

	var body: some View {
		HStack(spacing: 8) {
			Text("+\(file.additions)")
				.foregroundStyle(.green)
			Text("−\(file.deletions)")
				.foregroundStyle(.red)
		}
		.font(.caption.weight(.semibold).monospacedDigit())
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(file.additions) additions, \(file.deletions) deletions")
	}
}

private struct CommitDiffLineView: View {
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
