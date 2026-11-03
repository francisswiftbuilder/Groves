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
				Text("Couldn’t complete the Git action.").font(.callout)
				Spacer(minLength: 8)
				if message.localizedCaseInsensitiveContains("settings") {
					SettingsLink { Text("Open Settings") }
				}
				Button(showsDetails ? "Hide Details" : "Details") { showsDetails.toggle() }
				Button("Dismiss", systemImage: "xmark", action: onDismiss)
					.labelStyle(.iconOnly)
					.buttonStyle(.plain)
					.help("Dismiss")
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
