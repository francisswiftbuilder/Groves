import SwiftUI

struct CommitGraphReference: View {
	let reference: String

	var body: some View {
		Label(displayName, systemImage: systemImage)
			.labelStyle(.titleAndIcon)
			.font(.caption2.weight(.medium))
			.lineLimit(1)
			.truncationMode(.middle)
			.foregroundStyle(referenceColor)
			.padding(.horizontal, 7)
			.padding(.vertical, 2)
			.background(referenceColor.opacity(0.10), in: Capsule())
			.frame(maxWidth: 132)
			.help(reference)
	}

	private var referenceColor: Color {
		if reference.contains("HEAD") {
			return Color(nsColor: .controlAccentColor)
		}
		if reference.contains("tag:") {
			return .orange
		}
		if reference.contains("origin/") {
			return .blue
		}
		return Color(nsColor: .secondaryLabelColor)
	}

	private var displayName: String {
		reference
			.replacingOccurrences(of: "HEAD -> ", with: "")
			.replacingOccurrences(of: "tag: ", with: "")
	}

	private var systemImage: String {
		if reference.contains("tag:") {
			return "tag.fill"
		}
		if reference.contains("origin/") {
			return "cloud.fill"
		}
		return "arrow.triangle.branch"
	}
}
