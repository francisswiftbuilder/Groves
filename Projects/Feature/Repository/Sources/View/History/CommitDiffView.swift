import SwiftUI

struct CommitDiffView: View {
	let file: CommitDiffFile?
	let changedFileCount: Int
	let isLoading: Bool

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
		if isLoading {
			LoadingStateView(
				title: "Loading Commit Diff",
				message: "Reading the files changed by this commit."
			)
		} else if file != nil {
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
