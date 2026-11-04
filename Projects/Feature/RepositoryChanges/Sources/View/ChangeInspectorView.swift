import CoreRepositoryUI
import DomainGitInterface
import Foundation
import SwiftUI

struct ChangeInspectorView: View {
	let fileName: String?
	let filePath: String?
	let fileState: GitFileState?
	let isStaged: Bool
	let selectedCount: Int
	let additionCount: Int
	let deletionCount: Int
	let isLoading: Bool

	var body: some View {
		VStack(spacing: 0) {
			inspectorContent
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.safeAreaInset(edge: .top, spacing: 0) {
			VStack(spacing: 0) {
				inspectorHeader
				Divider()
			}
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
		if selectedCount > 1 {
			EmptyStateView(
				title: "Multiple Files Selected",
				systemImage: "doc.on.doc"
			)
		} else if let fileName, let filePath, let fileState {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					fileIdentity(
						fileName: fileName,
						filePath: filePath
					)
					.padding(16)

					Divider()

					inspectorSection("Information") {
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
							if isLoading {
								ProgressView().controlSize(.small)
									.accessibilityLabel("Refreshing change statistics")
							}
						}
						.font(.subheadline.weight(.semibold).monospacedDigit())
					}
					.padding(16)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.id(filePath)
		} else {
			EmptyStateView(
				title: "No File Selected",
				systemImage: "doc.text"
			)
		}
	}

	private func fileIdentity(
		fileName: String,
		filePath: String
	) -> some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: fileSymbol)
				.font(.title3)
				.foregroundStyle(.secondary)
				.frame(width: 24)
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				Text(fileName)
					.font(.headline)
					.lineLimit(2)
				Text(filePath)
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)
					.help(filePath)
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

}
