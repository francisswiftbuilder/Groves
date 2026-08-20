import DomainGitInterface
import Foundation
import SwiftUI

struct ChangeInspectorView: View {
	let fileName: String?
	let filePath: String?
	let fileState: GitFileState?
	let isStaged: Bool
	let selectedCount: Int
	let diff: String

	var body: some View {
		VStack(spacing: 0) {
			inspectorHeader
			Divider()
			inspectorContent
		}
	}

	private var inspectorHeader: some View {
		HStack {
			Text("File")
				.font(.subheadline.weight(.semibold))
			Spacer()
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
	}

	@ViewBuilder
	private var inspectorContent: some View {
		if selectedCount > 1 {
			EmptyStateView(
				title: "Multiple Files Selected",
				message: "Select one file to inspect its details.",
				systemImage: "doc.on.doc"
			)
		} else if let fileName, let filePath, let fileState {
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					fileIdentity(
						fileName: fileName,
						filePath: filePath,
						fileState: fileState
					)

					inspectorSection("Information") {
						InspectorValueRow("Location", value: filePath)
						InspectorValueRow("Status", value: fileState.inspectorTitle)
						InspectorValueRow("Staging", value: isStaged ? "Staged" : "Unstaged")
					}

					inspectorSection("Changes") {
						HStack(spacing: 10) {
							Text("+\(additionCount)")
								.foregroundStyle(.green)
							Text("−\(deletionCount)")
								.foregroundStyle(.red)
						}
						.font(.subheadline.weight(.semibold).monospacedDigit())
					}
				}
				.padding(16)
			}
		} else {
			EmptyStateView(
				title: "No File Selected",
				message: "Select a file to inspect its status and changes.",
				systemImage: "doc.text"
			)
		}
	}

	private func fileIdentity(
		fileName: String,
		filePath: String,
		fileState: GitFileState
	) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: fileSymbol)
				.font(.title2)
				.foregroundStyle(.secondary)
				.frame(width: 34, height: 42)

			VStack(alignment: .leading, spacing: 4) {
				Text(fileName)
					.font(.headline)
					.lineLimit(2)
				Text(filePath)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
				Text(fileState.inspectorTitle)
					.font(.caption.weight(.semibold))
					.foregroundStyle(statusColor)
			}
		}
	}

	private func inspectorSection<Content: View>(
		_ title: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.subheadline.weight(.semibold))
			content()
		}
	}

	private var fileSymbol: String {
		guard let filePath else { return "doc" }
		switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
		case "swift":
			return "swift"
		case "md", "txt", "json", "plist", "yml", "yaml":
			return "doc.text"
		case "png", "jpg", "jpeg", "gif", "webp":
			return "photo"
		default:
			return "doc"
		}
	}

	private var statusColor: Color {
		switch fileState {
		case .added, .copied, .untracked:
			return .green
		case .deleted:
			return .red
		case .modified, .renamed, .typeChanged:
			return .orange
		case .unmerged:
			return .purple
		case .ignored, .unchanged, .none:
			return .secondary
		}
	}

	private var additionCount: Int {
		DiffParser.parseSourceLines(diff).count { $0.kind == .addition }
	}

	private var deletionCount: Int {
		DiffParser.parseSourceLines(diff).count { $0.kind == .deletion }
	}
}

private struct InspectorValueRow: View {
	let title: String
	let value: String

	init(_ title: String, value: String) {
		self.title = title
		self.value = value
	}

	var body: some View {
		LabeledContent(title) {
			Text(value)
				.multilineTextAlignment(.trailing)
				.textSelection(.enabled)
		}
		.font(.caption)
		.foregroundStyle(.secondary)
	}
}

extension GitFileState {
	fileprivate var inspectorTitle: String {
		switch self {
		case .added:
			return "Added"
		case .copied:
			return "Copied"
		case .deleted:
			return "Deleted"
		case .ignored:
			return "Ignored"
		case .modified:
			return "Modified"
		case .renamed:
			return "Renamed"
		case .typeChanged:
			return "Type Changed"
		case .unmerged:
			return "Unmerged"
		case .untracked:
			return "Untracked"
		case .unchanged:
			return "Unchanged"
		}
	}
}
