import SwiftUI

struct CommitGraphReference: View {
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast
	let descriptor: CommitGraphReferenceDescriptor

	var body: some View {
		HStack(spacing: 4) {
			Image(systemName: descriptor.systemImage)
				.foregroundStyle(descriptor.iconColor)
				.accessibilityHidden(true)

			Text(descriptor.name)
				.foregroundStyle(descriptor.textColor)
		}
		.font(.caption.weight(descriptor.fontWeight))
		.lineLimit(1)
		.padding(.horizontal, 7)
		.padding(.vertical, 3)
		.background(backgroundColor, in: Capsule())
		.fixedSize(horizontal: true, vertical: false)
		.help(descriptor.helpText)
		.accessibilityElement(children: .combine)
		.accessibilityLabel(descriptor.accessibilityLabel)
	}

	private var backgroundColor: Color {
		if descriptor.kind == .currentBranch {
			return Color(nsColor: .controlAccentColor)
				.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
		}
		if descriptor.kind == .tag {
			return Color.orange.opacity(colorSchemeContrast == .increased ? 0.20 : 0.10)
		}
		return Color(nsColor: .quaternaryLabelColor)
			.opacity(colorSchemeContrast == .increased ? 0.30 : 0.16)
	}
}
