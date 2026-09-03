import SwiftUI

struct RepositoryNoticeBanner: View {
	let message: String
	let onDismiss: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				Image(systemName: "key.slash")
					.foregroundStyle(.orange)
					.accessibilityHidden(true)
				Text(message)
					.font(.callout)
					.frame(maxWidth: .infinity, alignment: .leading)
				SettingsLink { Text("Open Settings") }
				Button("Dismiss") { onDismiss() }
			}
			Divider()
		}
		.padding(.horizontal, 12)
		.padding(.top, 8)
		.background(.bar)
		.accessibilityElement(children: .contain)
	}
}
