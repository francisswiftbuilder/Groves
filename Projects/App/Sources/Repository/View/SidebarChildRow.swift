import SwiftUI

struct SidebarChildRow: View {
	let title: String
	let systemImage: String
	let accessory: String?

	var body: some View {
		HStack {
			Label {
				Text(title).lineLimit(1).truncationMode(.middle)
			} icon: {
				Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
			}
			if let accessory {
				Spacer(minLength: 8)
				Text(accessory)
					.font(.caption)
					.monospacedDigit()
					.foregroundStyle(.secondary)
					.fixedSize()
			}
		}
		.contentShape(.rect)
	}
}
