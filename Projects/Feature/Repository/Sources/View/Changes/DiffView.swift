import DomainGitInterface
import SwiftUI

struct DiffView: View {
	let diff: String
	let changedFileCount: Int
	let fileName: String?
	let filePath: String?
	let fileState: GitFileState?
	let fileActionTitle: String?
	let lineAction: GitDiffLineAction?
	let isLoading: Bool
	let onApplyFileAction: () -> Void
	let onApplyLine: (GitDiffLineSelection, GitDiffLineAction) -> Void

	var body: some View {
		VStack(spacing: 0) {
			diffHeader
			Divider()
			diffContent
		}
		.safeAreaInset(edge: .bottom) {
			if !diff.isEmpty {
				diffFooter
			}
		}
	}

	private var diffFooter: some View {
		VStack(spacing: 0) {
			Divider()
			HStack(spacing: 12) {
				Text("\(changedFileCount) files with changes")
					.foregroundStyle(.secondary)
				Spacer(minLength: 16)
				DiffStatisticsView(diffLines: diffLines)
			}
			.font(.caption)
			.padding(.horizontal, 16)
			.frame(height: 40)
		}
		.background(.bar)
	}

	@ViewBuilder
	private var diffHeader: some View {
		if let fileName {
			HStack(spacing: 10) {
				if let fileState {
					GitStatusBadge(state: fileState)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(fileName)
						.font(.subheadline.weight(.semibold))
						.lineLimit(1)
					if let filePath {
						Text(filePath)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 12)

				if !diff.isEmpty {
					DiffStatisticsView(diffLines: diffLines)
				}

				if let fileActionTitle {
					Button(fileActionTitle, action: onApplyFileAction)
						.buttonStyle(.bordered)
						.controlSize(.small)
						.disabled(isLoading)
				}
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
		} else {
			HStack {
				Text("Diff")
					.font(.subheadline.weight(.semibold))
				Spacer()
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
		}
	}

	@ViewBuilder
	private var diffContent: some View {
		if diff.isEmpty {
			EmptyStateView(
				title: "No Diff Selected",
				message: "Select a tracked text change to inspect its diff.",
				systemImage: "doc.text.magnifyingglass"
			)
		} else if diffLines.isEmpty {
			EmptyStateView(
				title: "Empty File",
				message: "This file has no content.",
				systemImage: "doc"
			)
		} else {
			GeometryReader { geometry in
				ScrollView([.horizontal, .vertical]) {
					VStack(alignment: .leading, spacing: 0) {
						ForEach(diffLines) { line in
							DiffLineView(
								line: line,
								showsOldLineNumbers: showsOldLineNumbers,
								showsNewLineNumbers: showsNewLineNumbers,
								action: lineAction,
								isLoading: isLoading,
								onApply: onApplyLine
							)
						}
					}
					.padding(.vertical, 8)
					.frame(minWidth: max(geometry.size.width, 0), alignment: .leading)
				}
				.defaultScrollAnchor(.topLeading)
			}
		}
	}

	private var diffLines: [DiffLine] {
		DiffParser.parseSourceLines(diff)
	}

	private var showsOldLineNumbers: Bool {
		diffLines.contains { $0.oldLineNumber != nil }
	}

	private var showsNewLineNumbers: Bool {
		diffLines.contains { $0.newLineNumber != nil }
	}

}

private struct DiffStatisticsView: View {
	let diffLines: [DiffLine]

	var body: some View {
		HStack(spacing: 8) {
			Text("+\(additionCount)")
				.foregroundStyle(.green)
			Text("−\(deletionCount)")
				.foregroundStyle(.red)
		}
		.font(.caption.weight(.semibold).monospacedDigit())
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(additionCount) additions, \(deletionCount) deletions")
	}

	private var additionCount: Int {
		diffLines.count { $0.kind == .addition }
	}

	private var deletionCount: Int {
		diffLines.count { $0.kind == .deletion }
	}
}

enum DiffLineKind: Equatable {
	case metadata
	case hunk
	case context
	case addition
	case deletion
}

struct DiffLine: Identifiable {
	let number: Int
	let text: String
	let oldLineNumber: Int?
	let newLineNumber: Int?
	let kind: DiffLineKind
	var selection: GitDiffLineSelection?
	var showsAction = false

	var id: Int { number }

	var sourceText: String {
		guard isSourceLine else { return text }
		return String(text.dropFirst())
	}

	var isSourceLine: Bool {
		switch kind {
		case .context, .addition, .deletion:
			return true
		case .metadata, .hunk:
			return false
		}
	}
}

enum DiffParser {
	static func parseSourceLines(_ diff: String) -> [DiffLine] {
		parse(diff).filter(\.isSourceLine)
	}

	static func parse(_ diff: String) -> [DiffLine] {
		let sourceLines = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		var oldLineNumber: Int?
		var newLineNumber: Int?
		var lines: [DiffLine] = []

		for (number, text) in sourceLines.enumerated() {
			if let hunkStart = parseHunkStart(text) {
				oldLineNumber = hunkStart.old
				newLineNumber = hunkStart.new
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: nil,
						newLineNumber: nil,
						kind: .hunk,
						selection: nil
					)
				)
				continue
			}

			guard let currentOldLineNumber = oldLineNumber,
				let currentNewLineNumber = newLineNumber
			else {
				lines.append(metadataLine(number: number, text: text))
				continue
			}

			if text.hasPrefix("-") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: nil,
						kind: .deletion,
						selection: nil
					)
				)
				oldLineNumber = currentOldLineNumber + 1
				continue
			}

			if text.hasPrefix("+") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: nil,
						newLineNumber: currentNewLineNumber,
						kind: .addition,
						selection: nil
					)
				)
				newLineNumber = currentNewLineNumber + 1
				continue
			}

			if text.hasPrefix(" ") {
				lines.append(
					DiffLine(
						number: number,
						text: text,
						oldLineNumber: currentOldLineNumber,
						newLineNumber: currentNewLineNumber,
						kind: .context,
						selection: nil
					)
				)
				oldLineNumber = currentOldLineNumber + 1
				newLineNumber = currentNewLineNumber + 1
				continue
			}

			lines.append(metadataLine(number: number, text: text))
		}

		return pairChangedLines(lines)
	}

	private static func pairChangedLines(_ sourceLines: [DiffLine]) -> [DiffLine] {
		var lines = sourceLines
		var index = 0

		while index < lines.count {
			guard isChangedLine(lines[index]) else {
				index += 1
				continue
			}

			let startIndex = index
			while index < lines.count, isChangedLine(lines[index]) {
				index += 1
			}

			let changedIndices = Array(startIndex..<index)
			let deletionIndices = changedIndices.filter { lines[$0].kind == .deletion }
			let additionIndices = changedIndices.filter { lines[$0].kind == .addition }
			let pairedCount = min(deletionIndices.count, additionIndices.count)

			for pairIndex in 0..<pairedCount {
				let deletionIndex = deletionIndices[pairIndex]
				let additionIndex = additionIndices[pairIndex]
				let selection = GitDiffLineSelection(
					oldLineNumber: lines[deletionIndex].oldLineNumber,
					newLineNumber: lines[additionIndex].newLineNumber
				)
				lines[deletionIndex].selection = selection
				lines[additionIndex].selection = selection
				lines[deletionIndex].showsAction = true
			}

			for deletionIndex in deletionIndices.dropFirst(pairedCount) {
				lines[deletionIndex].selection = GitDiffLineSelection(
					oldLineNumber: lines[deletionIndex].oldLineNumber,
					newLineNumber: nil
				)
				lines[deletionIndex].showsAction = true
			}

			for additionIndex in additionIndices.dropFirst(pairedCount) {
				lines[additionIndex].selection = GitDiffLineSelection(
					oldLineNumber: nil,
					newLineNumber: lines[additionIndex].newLineNumber
				)
				lines[additionIndex].showsAction = true
			}
		}

		return lines
	}

	private static func isChangedLine(_ line: DiffLine) -> Bool {
		line.kind == .addition || line.kind == .deletion
	}

	private static func metadataLine(number: Int, text: String) -> DiffLine {
		DiffLine(
			number: number,
			text: text,
			oldLineNumber: nil,
			newLineNumber: nil,
			kind: .metadata,
			selection: nil
		)
	}

	private static func parseHunkStart(_ line: String) -> (old: Int, new: Int)? {
		guard line.hasPrefix("@@ ") else { return nil }
		let components = line.split(separator: " ")
		guard components.count >= 3,
			let old = parseRangeStart(components[1], prefix: "-"),
			let new = parseRangeStart(components[2], prefix: "+")
		else { return nil }
		return (old, new)
	}

	private static func parseRangeStart(_ range: Substring, prefix: Character) -> Int? {
		guard range.first == prefix else { return nil }
		return Int(range.dropFirst().split(separator: ",", maxSplits: 1)[0])
	}
}

private struct DiffLineView: View {
	let line: DiffLine
	let showsOldLineNumbers: Bool
	let showsNewLineNumbers: Bool
	let action: GitDiffLineAction?
	let isLoading: Bool
	let onApply: (GitDiffLineSelection, GitDiffLineAction) -> Void

	var body: some View {
		HStack(spacing: 0) {
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

			Spacer(minLength: 12)
			lineActionButton
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
			.frame(width: 76, height: 20)
			.disabled(isLoading)
			.help(action.title)
			.accessibilityLabel(action.title)
		} else {
			Color.clear
				.frame(width: 76, height: 20)
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

extension GitDiffLineAction {
	fileprivate var title: String {
		switch self {
		case .stage:
			return "Stage Line"
		case .unstage:
			return "Unstage Line"
		}
	}

	fileprivate var systemImage: String {
		switch self {
		case .stage:
			return "plus"
		case .unstage:
			return "minus"
		}
	}

	fileprivate var buttonTitle: String {
		switch self {
		case .stage:
			return "Stage"
		case .unstage:
			return "Unstage"
		}
	}

	fileprivate var tint: Color {
		switch self {
		case .stage:
			return .accentColor
		case .unstage:
			return .orange
		}
	}
}
