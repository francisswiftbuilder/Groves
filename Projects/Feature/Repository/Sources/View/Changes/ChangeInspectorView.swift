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
	let isLoading: Bool

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
		.padding(.horizontal, 12)
		.frame(height: 52)
		.background(.bar)
	}

	@ViewBuilder
	private var inspectorContent: some View {
		if isLoading {
			LoadingStateView(
				title: "Loading File",
				message: "Reading file information and change statistics."
			)
		} else if selectedCount > 1 {
			EmptyStateView(
				title: "Multiple Files Selected",
				message: "Select one file to inspect its details.",
				systemImage: "doc.on.doc"
			)
		} else if let fileName, let filePath, let fileState {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					fileIdentity(
						fileName: fileName,
						filePath: filePath,
						fileState: fileState
					)
					.padding(16)

					Divider()

					inspectorSection("Information") {
						InspectorValueRow("Location", value: filePath)
						InspectorValueRow("Status", value: fileState.inspectorTitle)
						InspectorValueRow("Staging", value: isStaged ? "Staged" : "Unstaged")
					}
					.padding(16)

					Divider()

					inspectorSection("Changes") {
						HStack(spacing: 10) {
							Text("+\(additionCount)")
								.foregroundStyle(.green)
							Text("−\(deletionCount)")
								.foregroundStyle(.red)
						}
						.font(.subheadline.weight(.semibold).monospacedDigit())
					}
					.padding(16)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
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
				.font(.system(size: 28, weight: .light))
				.foregroundStyle(.secondary)
				.frame(width: 48, height: 54)

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
