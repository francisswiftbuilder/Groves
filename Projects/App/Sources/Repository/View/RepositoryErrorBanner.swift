import AppKit
import SwiftUI

struct RepositoryErrorBanner: View {
	let message: String
	let onDismiss: () -> Void
	@State private var showsDetails = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				Image(systemName: "exclamationmark.circle.fill")
					.foregroundStyle(.red)
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text("Git Couldn’t Complete the Action").font(.headline)
					Text("Review the details, update the repository state, and try again.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				if message.localizedCaseInsensitiveContains("settings") {
					SettingsLink { Text("Open Settings") }
				}
				Button("Details") { showsDetails.toggle() }
				Button("Dismiss") { onDismiss() }
			}
			if showsDetails {
				HStack(alignment: .top, spacing: 8) {
					Text(message)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
					Button {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(message, forType: .string)
					} label: {
						Label("Copy Error Details", systemImage: "doc.on.doc")
					}
					.labelStyle(.iconOnly)
					.help("Copy Error Details")
				}
			}
			Divider()
		}
		.padding(.horizontal, 12)
		.padding(.top, 8)
		.background(.bar)
		.accessibilityElement(children: .contain)
	}
}
